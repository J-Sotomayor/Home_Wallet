import {createHash, randomBytes} from "node:crypto";

import {initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getMessaging} from "firebase-admin/messaging";
import {
  DocumentReference,
  FieldValue,
  Timestamp,
  WriteResult,
  getFirestore,
} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {setGlobalOptions} from "firebase-functions/v2";
import {error as logError} from "firebase-functions/logger";
import {
  CallableRequest,
  HttpsError,
  onCall,
} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onDocumentCreated} from "firebase-functions/v2/firestore";

initializeApp();

const primaryRegion = "southamerica-west1";

setGlobalOptions({
  region: primaryRegion,
  maxInstances: 5,
  memory: "256MiB",
  timeoutSeconds: 30,
});

const db = getFirestore();
const invitationLifetimeMs = 15 * 60 * 1000;
const termsVersion = "2026-08-02";

function requireVerifiedUser(request: CallableRequest<unknown>): string {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }
  if (auth.token.email_verified !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Debes verificar tu correo antes de continuar.",
    );
  }
  return auth.uid;
}

function requestMap(request: CallableRequest<unknown>): Record<string, unknown> {
  if (!request.data || typeof request.data !== "object") {
    throw new HttpsError("invalid-argument", "Solicitud incompleta.");
  }
  return request.data as Record<string, unknown>;
}

function requiredString(
  data: Record<string, unknown>,
  key: string,
  maxLength: number,
): string {
  const value = data[key];
  if (typeof value !== "string" || value.length === 0 || value.length > maxLength) {
    throw new HttpsError("invalid-argument", `El campo ${key} no es válido.`);
  }
  return value;
}

function requiredCipherPayload(
  data: Record<string, unknown>,
  key: string,
): Record<string, unknown> {
  const value = data[key];
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "El contenido cifrado no es válido.");
  }
  const payload = value as Record<string, unknown>;
  const keys = Object.keys(payload).sort();
  const expected = ["alg", "ct", "iv", "tag", "v"];
  if (keys.length !== expected.length ||
      keys.some((item, index) => item !== expected[index]) ||
      payload.v !== 1 || payload.alg !== "A256GCM" ||
      typeof payload.ct !== "string" || payload.ct.length === 0 ||
      payload.ct.length > 100000 ||
      typeof payload.iv !== "string" || payload.iv.length < 12 ||
      payload.iv.length > 64 ||
      typeof payload.tag !== "string" || payload.tag.length < 16 ||
      payload.tag.length > 64) {
    throw new HttpsError("invalid-argument", "El contenido cifrado no es válido.");
  }
  return payload;
}

function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("base64url");
}

async function enforceRateLimit(
  uid: string,
  action: string,
  intervalMs: number,
): Promise<void> {
  const reference = db.collection("internalRateLimits").doc(`${uid}_${action}`);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const lastAt = snapshot.data()?.lastAt as Timestamp | undefined;
    if (lastAt && Date.now() - lastAt.toMillis() < intervalMs) {
      throw new HttpsError(
        "resource-exhausted",
        "Espera unos segundos antes de volver a intentarlo.",
      );
    }
    transaction.set(reference, {lastAt: Timestamp.now()}, {merge: true});
  });
}

async function activeMemberIds(householdId: string): Promise<string[]> {
  const members = await db
    .collection("households")
    .doc(householdId)
    .collection("members")
    .where("status", "==", "active")
    .get();
  return members.docs.map((member) => member.id);
}

async function sendPushToUsers(
  userIds: string[],
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  const uniqueUsers = [...new Set(userIds)].filter(Boolean);
  if (uniqueUsers.length === 0) return;
  const deviceSnapshots = await Promise.all(uniqueUsers.map((userId) =>
    db.collection("users").doc(userId).collection("devices").get()));
  const tokenReferences = new Map<string, DocumentReference>();
  for (const snapshot of deviceSnapshots) {
    for (const device of snapshot.docs) {
      const token = device.data().token;
      if (typeof token === "string" && token.length > 20) {
        tokenReferences.set(token, device.ref);
      }
    }
  }
  const tokens = [...tokenReferences.keys()];
  for (let index = 0; index < tokens.length; index += 500) {
    const group = tokens.slice(index, index + 500);
    const response = await getMessaging().sendEachForMulticast({
      tokens: group,
      notification: {title, body},
      data,
      android: {
        priority: "high",
        notification: {channelId: "homewallet_smart_alerts"},
      },
      apns: {payload: {aps: {sound: "default"}}},
    });
    const removals: Promise<WriteResult>[] = [];
    response.responses.forEach((item, responseIndex) => {
      const code = item.error?.code ?? "";
      if (code.includes("registration-token-not-registered") ||
          code.includes("invalid-registration-token")) {
        const reference = tokenReferences.get(group[responseIndex]);
        if (reference) removals.push(reference.delete());
      }
    });
    await Promise.all(removals);
  }
}

async function notifyHousehold(
  householdId: string,
  excludedUid: string | null,
  title: string,
  body: string,
  type: string,
): Promise<void> {
  const recipients = (await activeMemberIds(householdId))
    .filter((uid) => uid !== excludedUid);
  await sendPushToUsers(recipients, title, body, {householdId, type});
}

async function claimNotificationWindow(
  key: string,
  intervalMs: number,
): Promise<boolean> {
  const reference = db.collection("notificationRateLimits").doc(key);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const lastAt = snapshot.data()?.lastAt as Timestamp | undefined;
    if (lastAt && Date.now() - lastAt.toMillis() < intervalMs) return false;
    transaction.set(reference, {lastAt: Timestamp.now()}, {merge: true});
    return true;
  });
}

export const notifyNewTransaction = onDocumentCreated(
  "households/{householdId}/transactions/{transactionId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    if (!await claimNotificationWindow(
      `transaction-${event.params.householdId}`,
      60_000,
    )) return;
    await notifyHousehold(
      event.params.householdId,
      typeof data.createdBy === "string" ? data.createdBy : null,
      "Nuevo movimiento en tu espacio",
      "Revisa la actividad compartida en HomeWallet.",
      "transaction",
    );
  },
);

export const createHousehold = onCall(async (request) => {
  const uid = requireVerifiedUser(request);
  const data = requestMap(request);
  const requestedKind = data.kind;
  const kind = ["individual", "family", "couple", "group"].includes(requestedKind as string) ?
    requestedKind as string : "family";
  await enforceRateLimit(uid, "createHousehold", 10_000);

  const userReference = db.collection("users").doc(uid);
  const householdReference = db.collection("households").doc();
  const memberReference = householdReference.collection("members").doc(uid);

  await db.runTransaction(async (transaction) => {
    const userSnapshot = await transaction.get(userReference);
    const userData = userSnapshot.data();
    const householdIds = (userData?.householdIds ?? []) as string[];
    if (kind === "individual") {
      const registeredIndividual = userData?.individualHouseholdId;
      if (typeof registeredIndividual === "string" && registeredIndividual.length > 0) {
        throw new HttpsError(
          "already-exists",
          "Ya tienes un espacio Individual.",
        );
      }
      const existingHouseholds = await Promise.all(
        householdIds.map((householdId) =>
          transaction.get(db.collection("households").doc(householdId))),
      );
      const existingIndividuals = existingHouseholds
        .filter((snapshot) => snapshot.exists && snapshot.data()?.kind === "individual");
      if (existingIndividuals.length > 0) {
        throw new HttpsError(
          "already-exists",
          existingIndividuals.length === 1 ?
            "Ya tienes un espacio Individual." :
            "Tu cuenta tiene varios espacios Individual heredados y requiere revisión antes de crear otro.",
        );
      }
    }
    transaction.create(householdReference, {
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      keyVersion: 1,
      memberCount: 1,
      kind,
    });
    transaction.create(memberReference, {
      uid,
      role: "owner",
      status: "active",
      joinedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(
      userReference,
      {
        householdIds: FieldValue.arrayUnion(householdReference.id),
        ...(kind === "individual" ?
          {individualHouseholdId: householdReference.id} : {}),
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  });

  return {householdId: householdReference.id};
});

export const createInvitation = onCall(async (request) => {
  const uid = requireVerifiedUser(request);
  const data = requestMap(request);
  const householdId = requiredString(data, "householdId", 128);
  const requestedRole = data.role === "junior" ? "junior" : "member";
  await enforceRateLimit(uid, "createInvitation", 5_000);

  const token = randomBytes(32).toString("base64url");
  const expiresAt = Timestamp.fromMillis(Date.now() + invitationLifetimeMs);
  const householdReference = db.collection("households").doc(householdId);
  const memberReference = householdReference.collection("members").doc(uid);
  // Un único documento por hogar invalida inmediatamente el QR anterior.
  const invitationReference = db.collection("invitations").doc(householdId);
  let kind = "family";
  let role = "member";
  await db.runTransaction(async (transaction) => {
    const [household, member] = await Promise.all([
      transaction.get(householdReference),
      transaction.get(memberReference),
    ]);
    if (!household.exists) {
      throw new HttpsError("not-found", "El espacio ya no existe.");
    }
    if (member.data()?.status !== "active" ||
        !["owner", "admin"].includes(member.data()?.role as string)) {
      throw new HttpsError(
        "permission-denied",
        "Solo un administrador puede invitar integrantes.",
      );
    }
    kind = household.data()?.kind ?? "family";
    if (kind === "individual") {
      throw new HttpsError(
        "failed-precondition",
        "Un espacio Individual no puede generar invitaciones. Crea primero un espacio compartido.",
      );
    }
    if (kind === "couple" && (household.data()?.memberCount ?? 0) >= 2) {
      throw new HttpsError(
        "resource-exhausted",
        "Un espacio Pareja admite como máximo dos integrantes.",
      );
    }
    role = kind === "family" ? requestedRole : "member";
    transaction.set(invitationReference, {
      householdId,
      tokenHash: hashToken(token),
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt,
      status: "active",
      role,
      usedBy: null,
      usedAt: null,
    });
  });

  return {
    invitationId: invitationReference.id,
    householdId,
    token,
    expiresAt: expiresAt.toMillis(),
    kind,
    role,
  };
});

export const revokeInvitation = onCall(async (request) => {
  const uid = requireVerifiedUser(request);
  const data = requestMap(request);
  const householdId = requiredString(data, "householdId", 128);
  await enforceRateLimit(uid, "revokeInvitation", 2_000);

  const householdReference = db.collection("households").doc(householdId);
  const memberReference = householdReference.collection("members").doc(uid);
  const invitationReference = db.collection("invitations").doc(householdId);
  await db.runTransaction(async (transaction) => {
    const [household, member, invitation] = await Promise.all([
      transaction.get(householdReference),
      transaction.get(memberReference),
      transaction.get(invitationReference),
    ]);
    if (!household.exists) {
      throw new HttpsError("not-found", "El espacio ya no existe.");
    }
    if (member.data()?.status !== "active" ||
        !["owner", "admin"].includes(member.data()?.role as string)) {
      throw new HttpsError(
        "permission-denied",
        "Solo un administrador puede revocar invitaciones.",
      );
    }
    if (!invitation.exists || invitation.data()?.status !== "active") return;
    transaction.update(invitationReference, {
      status: "revoked",
      revokedBy: uid,
      revokedAt: FieldValue.serverTimestamp(),
    });
  });
  return {ok: true};
});

export const acceptInvitation = onCall(async (request) => {
  const uid = requireVerifiedUser(request);
  const data = requestMap(request);
  const invitationId = requiredString(data, "invitationId", 128);
  const token = requiredString(data, "token", 256);
  if (token.length < 32) {
    throw new HttpsError("invalid-argument", "Token de invitación inválido.");
  }
  await enforceRateLimit(uid, "acceptInvitation", 3_000);

  const invitationReference = db.collection("invitations").doc(invitationId);
  const userReference = db.collection("users").doc(uid);
  let acceptedHouseholdId = "";

  await db.runTransaction(async (transaction) => {
    const invitationSnapshot = await transaction.get(invitationReference);
    if (!invitationSnapshot.exists) {
      throw new HttpsError("not-found", "La invitación no existe.");
    }
    const invitation = invitationSnapshot.data()!;
    if (invitation.status === "revoked") {
      throw new HttpsError(
        "failed-precondition",
        "La invitación fue revocada. Solicita una nueva.",
      );
    }
    if (invitation.status !== "active" || invitation.usedBy !== null) {
      throw new HttpsError("already-exists", "La invitación ya fue utilizada.");
    }
    const expiresAt = invitation.expiresAt as Timestamp;
    if (expiresAt.toMillis() <= Date.now()) {
      throw new HttpsError("deadline-exceeded", "La invitación venció.");
    }
    if (invitation.tokenHash !== hashToken(token)) {
      throw new HttpsError("permission-denied", "La invitación no es válida.");
    }

    const householdId = invitation.householdId as string;
    acceptedHouseholdId = householdId;
    const householdReference = db.collection("households").doc(householdId);
    const memberReference = householdReference.collection("members").doc(uid);
    const [householdSnapshot, memberSnapshot] = await Promise.all([
      transaction.get(householdReference),
      transaction.get(memberReference),
    ]);
    if (!householdSnapshot.exists) {
      throw new HttpsError("not-found", "El espacio ya no existe.");
    }
    const kind = householdSnapshot.data()?.kind ?? "family";
    if (kind === "individual") {
      throw new HttpsError(
        "failed-precondition",
        "No es posible incorporarse a un espacio Individual.",
      );
    }
    const invitedRole = invitation.role === "junior" ? "junior" : "member";
    const role = kind === "family" ? invitedRole : "member";
    const alreadyMember =
      memberSnapshot.exists && memberSnapshot.data()?.status === "active";
    if (!alreadyMember && kind === "couple" &&
        (householdSnapshot.data()?.memberCount ?? 0) >= 2) {
      throw new HttpsError(
        "resource-exhausted",
        "El espacio Pareja ya tiene dos integrantes.",
      );
    }

    if (!alreadyMember) {
      transaction.set(memberReference, {
        uid,
        role,
        status: "active",
        joinedAt: FieldValue.serverTimestamp(),
      });
      transaction.update(householdReference, {
        memberCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(
        userReference,
        {
          householdIds: FieldValue.arrayUnion(householdId),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }
    transaction.update(invitationReference, {
      status: "used",
      usedBy: uid,
      usedAt: FieldValue.serverTimestamp(),
    });
  });

  await notifyHousehold(
    acceptedHouseholdId,
    uid,
    "Nuevo integrante en el espacio",
    "Una invitación fue aceptada. Revisa la lista de integrantes.",
    "invitation-accepted",
  ).catch((error) => logError("Invitation notification failed", {error}));

  return {householdId: acceptedHouseholdId};
});

export const updateHouseholdKind = onCall(async (request) => {
  const uid = requireVerifiedUser(request);
  const data = requestMap(request);
  const householdId = requiredString(data, "householdId", 128);
  const kind = requiredString(data, "kind", 20);
  const privatePayload = requiredCipherPayload(data, "privatePayload");
  if (!["individual", "family", "couple", "group"].includes(kind)) {
    throw new HttpsError("invalid-argument", "El tipo de espacio no es válido.");
  }
  await enforceRateLimit(uid, "updateHouseholdKind", 2_000);

  const householdReference = db.collection("households").doc(householdId);
  const ownerReference = householdReference.collection("members").doc(uid);
  const activeMembersQuery = householdReference
    .collection("members")
    .where("status", "==", "active");

  await db.runTransaction(async (transaction) => {
    const [household, owner, activeMembers] = await Promise.all([
      transaction.get(householdReference),
      transaction.get(ownerReference),
      transaction.get(activeMembersQuery),
    ]);
    if (!household.exists) {
      throw new HttpsError("not-found", "El espacio ya no existe.");
    }
    if (owner.data()?.status !== "active" || owner.data()?.role !== "owner") {
      throw new HttpsError(
        "permission-denied",
        "Solo el propietario puede cambiar el tipo de espacio.",
      );
    }
    const currentKind = household.data()?.kind ?? "family";
    if ((currentKind === "individual") !== (kind === "individual")) {
      throw new HttpsError(
        "failed-precondition",
        "Individual no puede convertirse ni recibir datos de un espacio compartido. Crea otro espacio para conservar la separación.",
      );
    }
    if (kind === "couple" &&
        ((household.data()?.memberCount ?? 0) > 2 || activeMembers.size > 2)) {
      throw new HttpsError(
        "failed-precondition",
        "Pareja admite como máximo dos integrantes.",
      );
    }
    if (kind !== "family" &&
        activeMembers.docs.some((member) => member.data().role === "junior")) {
      throw new HttpsError(
        "failed-precondition",
        "Cambia primero el rol de Integrante Jr.; ese rol solo está disponible en Familia.",
      );
    }
    transaction.update(householdReference, {
      kind,
      privatePayload,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return {ok: true, kind};
});

export const updateMemberRole = onCall(async (request) => {
  const uid = requireVerifiedUser(request);
  const data = requestMap(request);
  const householdId = requiredString(data, "householdId", 128);
  const memberId = requiredString(data, "memberId", 128);
  const role = requiredString(data, "role", 20);
  if (!["admin", "member", "junior"].includes(role)) {
    throw new HttpsError("invalid-argument", "El rol seleccionado no es válido.");
  }
  if (memberId === uid) {
    throw new HttpsError("failed-precondition", "No puedes cambiar tu propio rol.");
  }
  await enforceRateLimit(uid, "updateMemberRole", 2_000);

  const householdReference = db.collection("households").doc(householdId);
  const actorReference = householdReference.collection("members").doc(uid);
  const targetReference = householdReference.collection("members").doc(memberId);
  await db.runTransaction(async (transaction) => {
    const [household, actor, target] = await Promise.all([
      transaction.get(householdReference),
      transaction.get(actorReference),
      transaction.get(targetReference),
    ]);
    if (!household.exists || !target.exists || target.data()?.status !== "active") {
      throw new HttpsError("not-found", "El integrante ya no pertenece al espacio.");
    }
    if (actor.data()?.status !== "active" || actor.data()?.role !== "owner") {
      throw new HttpsError(
        "permission-denied",
        "Solo el propietario puede cambiar roles.",
      );
    }
    if (target.data()?.role === "owner") {
      throw new HttpsError("failed-precondition", "No se puede modificar al propietario.");
    }
    if (role === "junior" && (household.data()?.kind ?? "family") !== "family") {
      throw new HttpsError(
        "failed-precondition",
        "Integrante Jr está disponible únicamente para espacios Familia.",
      );
    }
    transaction.update(targetReference, {
      role,
      roleUpdatedAt: FieldValue.serverTimestamp(),
      roleUpdatedBy: uid,
    });
  });
  await sendPushToUsers(
    [memberId],
    "Tu rol cambió",
    "Revisa tus permisos actualizados en HomeWallet.",
    {householdId, type: "role-changed"},
  ).catch((error) => logError("Role notification failed", {error}));
  return {ok: true};
});

export const removeMember = onCall(async (request) => {
  const uid = requireVerifiedUser(request);
  const data = requestMap(request);
  const householdId = requiredString(data, "householdId", 128);
  const memberId = requiredString(data, "memberId", 128);
  if (memberId === uid) {
    throw new HttpsError(
      "failed-precondition",
      "Para salir del espacio usa la opción Salir del espacio.",
    );
  }
  await enforceRateLimit(uid, "removeMember", 2_000);

  const householdReference = db.collection("households").doc(householdId);
  const actorReference = householdReference.collection("members").doc(uid);
  const targetReference = householdReference.collection("members").doc(memberId);
  const userReference = db.collection("users").doc(memberId);
  await db.runTransaction(async (transaction) => {
    const [actor, target, targetUser] = await Promise.all([
      transaction.get(actorReference),
      transaction.get(targetReference),
      transaction.get(userReference),
    ]);
    if (actor.data()?.status !== "active" || actor.data()?.role !== "owner") {
      throw new HttpsError(
        "permission-denied",
        "Solo el propietario puede eliminar integrantes.",
      );
    }
    if (!target.exists || target.data()?.status !== "active") {
      throw new HttpsError("not-found", "El integrante ya no pertenece al espacio.");
    }
    if (target.data()?.role === "owner") {
      throw new HttpsError("failed-precondition", "No se puede eliminar al propietario.");
    }
    transaction.update(targetReference, {
      status: "removed",
      removedAt: FieldValue.serverTimestamp(),
      removedBy: uid,
    });
    transaction.update(householdReference, {
      memberCount: FieldValue.increment(-1),
      updatedAt: FieldValue.serverTimestamp(),
    });
    const userUpdate: Record<string, unknown> = {
      householdIds: FieldValue.arrayRemove(householdId),
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (targetUser.data()?.activeHouseholdId === householdId) {
      const remainingHouseholds = ((targetUser.data()?.householdIds ?? []) as string[])
        .filter((id) => id !== householdId);
      userUpdate.activeHouseholdId = remainingHouseholds[0] ?? null;
    }
    transaction.set(userReference, userUpdate, {merge: true});
  });
  await sendPushToUsers(
    [memberId],
    "Acceso al espacio actualizado",
    "Ya no formas parte de uno de tus espacios en HomeWallet.",
    {householdId, type: "member-removed"},
  ).catch((error) => logError("Removal notification failed", {error}));
  return {ok: true};
});

export const leaveHousehold = onCall(async (request) => {
  const uid = requireVerifiedUser(request);
  const data = requestMap(request);
  const householdId = requiredString(data, "householdId", 128);
  await enforceRateLimit(uid, "leaveHousehold", 2_000);

  const householdReference = db.collection("households").doc(householdId);
  const memberReference = householdReference.collection("members").doc(uid);
  const userReference = db.collection("users").doc(uid);
  await db.runTransaction(async (transaction) => {
    const [member, user] = await Promise.all([
      transaction.get(memberReference),
      transaction.get(userReference),
    ]);
    if (!member.exists || member.data()?.status !== "active") {
      throw new HttpsError("not-found", "Ya no perteneces a este espacio.");
    }
    if (member.data()?.role === "owner") {
      throw new HttpsError(
        "failed-precondition",
        "El propietario debe transferir o eliminar el espacio antes de salir.",
      );
    }
    transaction.update(memberReference, {
      status: "left",
      leftAt: FieldValue.serverTimestamp(),
    });
    transaction.update(householdReference, {
      memberCount: FieldValue.increment(-1),
      updatedAt: FieldValue.serverTimestamp(),
    });
    const userUpdate: Record<string, unknown> = {
      householdIds: FieldValue.arrayRemove(householdId),
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (user.data()?.activeHouseholdId === householdId) {
      const remainingHouseholds = ((user.data()?.householdIds ?? []) as string[])
        .filter((id) => id !== householdId);
      userUpdate.activeHouseholdId = remainingHouseholds[0] ?? null;
    }
    transaction.set(userReference, userUpdate, {merge: true});
  });
  return {ok: true};
});

export const acceptTerms = onCall(async (request) => {
  const uid = requireVerifiedUser(request);
  const data = requestMap(request);
  const version = requiredString(data, "version", 20);
  if (version !== termsVersion) {
    throw new HttpsError("failed-precondition", "La versión de términos cambió.");
  }
  await db.collection("users").doc(uid).set({
    termsVersion: version,
    termsAcceptedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {ok: true};
});

export const requestAccountDeletion = onCall(async (request) => {
  const uid = requireVerifiedUser(request);
  await enforceRateLimit(uid, "requestAccountDeletion", 10_000);
  const requestedAt = new Date();
  const executeAfter = addBusinessDays(requestedAt, 3);
  const requestReference = db.collection("accountDeletionRequests").doc(uid);
  const userReference = db.collection("users").doc(uid);
  const batch = db.batch();
  batch.set(requestReference, {
    uid,
    status: "pending",
    requestedAt: Timestamp.fromDate(requestedAt),
    executeAfter: Timestamp.fromDate(executeAfter),
  });
  batch.set(userReference, {
    deletionRequestedAt: Timestamp.fromDate(requestedAt),
    deletionScheduledFor: Timestamp.fromDate(executeAfter),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await batch.commit();
  return {executeAfter: executeAfter.getTime()};
});

export const cancelAccountDeletion = onCall(async (request) => {
  const uid = requireVerifiedUser(request);
  const requestReference = db.collection("accountDeletionRequests").doc(uid);
  const requestSnapshot = await requestReference.get();
  if (requestSnapshot.data()?.status === "processing") {
    throw new HttpsError(
      "failed-precondition",
      "El borrado ya comenzó y no puede cancelarse.",
    );
  }
  const batch = db.batch();
  batch.delete(requestReference);
  batch.set(db.collection("users").doc(uid), {
    deletionRequestedAt: FieldValue.delete(),
    deletionScheduledFor: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await batch.commit();
  return {ok: true};
});

export const processAccountDeletions = onSchedule({
  schedule: "every 60 minutes",
  // Cloud Scheduler is not available in southamerica-west1.
  region: "us-central1",
  timeZone: "America/Guayaquil",
}, async () => {
  const due = await db
    .collection("accountDeletionRequests")
    .where("executeAfter", "<=", Timestamp.now())
    .limit(20)
    .get();
  for (const request of due.docs) {
    if (request.data().status !== "pending") continue;
    try {
      await request.ref.update({status: "processing"});
      await deleteAccountData(request.id);
    } catch (error) {
      logError("Account deletion failed", {error});
      await request.ref.set({
        status: "pending",
        lastErrorAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  }
});

export const notifyDueRecurring = onSchedule({
  schedule: "every 15 minutes",
  // Cloud Scheduler is not available in southamerica-west1.
  region: "us-central1",
  timeZone: "America/Guayaquil",
}, async () => {
  const due = await db
    .collectionGroup("recurring")
    .where("nextDueAt", "<=", Timestamp.now())
    .limit(100)
    .get();
  for (const recurring of due.docs) {
    const data = recurring.data();
    if (data.active !== true || typeof data.createdBy !== "string") continue;
    const householdId = recurring.ref.parent.parent?.id;
    const nextDueAt = data.nextDueAt as Timestamp | undefined;
    if (!householdId || !nextDueAt) continue;
    const stateId = hashToken(`${recurring.ref.path}:${nextDueAt.toMillis()}`);
    const stateReference = db.collection("recurringNotificationState").doc(stateId);
    if ((await stateReference.get()).exists) continue;
    await stateReference.create({
      recurringPath: recurring.ref.path,
      dueAt: nextDueAt,
      notifiedAt: FieldValue.serverTimestamp(),
    });
    try {
      await sendPushToUsers(
        [data.createdBy],
        data.confirmBeforePosting === true ?
          "Registro recurrente pendiente" :
          "Registro recurrente listo",
        data.confirmBeforePosting === true ?
          "Abre HomeWallet para revisarlo y validarlo." :
          "Se validará automáticamente cuando abras HomeWallet.",
        {householdId, type: "recurring-due", recurringId: recurring.id},
      );
    } catch (error) {
      await stateReference.delete().catch(() => undefined);
      logError("Recurring notification failed", {error});
    }
  }
});

function addBusinessDays(value: Date, days: number): Date {
  const result = new Date(value);
  let remaining = days;
  while (remaining > 0) {
    result.setUTCDate(result.getUTCDate() + 1);
    const weekday = result.getUTCDay();
    if (weekday !== 0 && weekday !== 6) remaining--;
  }
  return result;
}

async function deleteAccountData(uid: string): Promise<void> {
  const userReference = db.collection("users").doc(uid);
  const userSnapshot = await userReference.get();
  const householdIds = (userSnapshot.data()?.householdIds ?? []) as string[];
  for (const householdId of householdIds) {
    const householdReference = db.collection("households").doc(householdId);
    const memberReference = householdReference.collection("members").doc(uid);
    const memberSnapshot = await memberReference.get();
    if (!memberSnapshot.exists || memberSnapshot.data()?.status !== "active") continue;
    const memberRole = memberSnapshot.data()?.role;
    const activeMembers = await householdReference
      .collection("members")
      .where("status", "==", "active")
      .get();
    const others = activeMembers.docs.filter((member) => member.id !== uid);
    if (memberRole === "owner" && others.length === 0) {
      await db.recursiveDelete(householdReference);
      await db.collection("invitations").doc(householdId).delete().catch(() => undefined);
      continue;
    }
    const batch = db.batch();
    if (memberRole === "owner" && others.length > 0) {
      const successor = [...others].sort((left, right) =>
        rolePriority(left.data().role) - rolePriority(right.data().role))[0];
      batch.update(successor.ref, {
        role: "owner",
        roleUpdatedAt: FieldValue.serverTimestamp(),
        roleUpdatedBy: "account-deletion",
      });
    }
    batch.update(memberReference, {
      status: "deleted-account",
      removedAt: FieldValue.serverTimestamp(),
    });
    batch.update(householdReference, {
      memberCount: FieldValue.increment(-1),
      updatedAt: FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  await getStorage().bucket().deleteFiles({prefix: `profilePhotos/${uid}/`});
  await userReference.delete();
  await db.collection("accountDeletionRequests").doc(uid).delete();
  await getAuth().deleteUser(uid);
}

function rolePriority(role: unknown): number {
  if (role === "admin") return 0;
  if (role === "member") return 1;
  return 2;
}
