import {readFileSync} from "node:fs";
import {after, beforeEach, test} from "node:test";
import assert from "node:assert/strict";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  Timestamp,
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  updateDoc,
} from "firebase/firestore";

const [host = "127.0.0.1", portText = "8080"] =
  (process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080").split(":");

const environment = await initializeTestEnvironment({
  projectId: "homewallet-prod",
  firestore: {
    host,
    port: Number(portText),
    rules: readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8"),
  },
});

const cipher = {
  v: 1,
  alg: "A256GCM",
  ct: "Y2lwaGVydGV4dA",
  iv: "MTIzNDU2Nzg5MDEy",
  tag: "MTIzNDU2Nzg5MDEyMzQ1Ng",
};

async function seedHousehold() {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "households/home"), {
      createdBy: "owner",
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
      keyVersion: 1,
      memberCount: 3,
      kind: "family",
      privatePayload: cipher,
    });
    await setDoc(doc(db, "households/home/members/owner"), {
      uid: "owner",
      role: "owner",
      status: "active",
      joinedAt: Timestamp.now(),
      privatePayload: cipher,
    });
    await setDoc(doc(db, "households/home/members/member"), {
      uid: "member",
      role: "member",
      status: "active",
      joinedAt: Timestamp.now(),
      privatePayload: cipher,
    });
    await setDoc(doc(db, "households/home/members/junior"), {
      uid: "junior",
      role: "junior",
      status: "active",
      joinedAt: Timestamp.now(),
      privatePayload: cipher,
    });
    await setDoc(doc(db, "households/home/transactions/record"), {
      schemaVersion: 1,
      type: "expense",
      occurredAt: Timestamp.now(),
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
      createdBy: "owner",
      payload: cipher,
    });
    await setDoc(doc(db, "invitations/secret"), {
      householdId: "home",
      tokenHash: "server-only",
    });
  });
}

beforeEach(async () => {
  await environment.clearFirestore();
  await seedHousehold();
});

after(async () => {
  await environment.cleanup();
});

test("rechaza lecturas sin autenticación o sin correo verificado", async () => {
  const anonymous = environment.unauthenticatedContext().firestore();
  const unverified = environment
    .authenticatedContext("owner", {email_verified: false})
    .firestore();

  await assertFails(getDoc(doc(anonymous, "households/home")));
  await assertFails(getDoc(doc(unverified, "households/home")));
});

test("permite al integrante ver el hogar y bloquea a terceros", async () => {
  const member = environment
    .authenticatedContext("member", {email_verified: true})
    .firestore();
  const outsider = environment
    .authenticatedContext("outsider", {email_verified: true})
    .firestore();

  const snapshot = await assertSucceeds(getDoc(doc(member, "households/home")));
  assert.equal(snapshot.exists(), true);
  await assertFails(getDoc(doc(outsider, "households/home")));
});

test("acepta una transacción cifrada y rechaza texto plano", async () => {
  const member = environment
    .authenticatedContext("member", {email_verified: true})
    .firestore();
  const base = {
    schemaVersion: 1,
    type: "expense",
    occurredAt: Timestamp.now(),
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    createdBy: "member",
  };

  await assertSucceeds(
    setDoc(doc(member, "households/home/transactions/encrypted"), {
      ...base,
      payload: cipher,
    }),
  );
  await assertFails(
    setDoc(doc(member, "households/home/transactions/plain"), {
      ...base,
      payload: {description: "Compra visible", amountMinor: 5000},
    }),
  );
});

test("impide modificar o borrar registros ajenos a un miembro común", async () => {
  const member = environment
    .authenticatedContext("member", {email_verified: true})
    .firestore();
  const reference = doc(member, "households/home/transactions/record");

  await assertFails(updateDoc(reference, {payload: cipher}));
  await assertFails(deleteDoc(reference));
});

test("Integrante Jr puede consultar pero no modificar finanzas", async () => {
  const junior = environment
    .authenticatedContext("junior", {email_verified: true})
    .firestore();
  await assertSucceeds(getDoc(doc(junior, "households/home/transactions/record")));
  await assertFails(
    setDoc(doc(junior, "households/home/transactions/junior-record"), {
      schemaVersion: 1,
      type: "expense",
      occurredAt: Timestamp.now(),
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
      createdBy: "junior",
      payload: cipher,
    }),
  );
  await assertFails(deleteDoc(doc(junior, "households/home/transactions/record")));
});

test("mantiene invitaciones y límites internos inaccesibles al cliente", async () => {
  const owner = environment
    .authenticatedContext("owner", {email_verified: true})
    .firestore();

  await assertFails(getDoc(doc(owner, "invitations/secret")));
  await assertFails(
    setDoc(doc(owner, "internalRateLimits/owner_createInvitation"), {
      lastAt: Timestamp.now(),
    }),
  );
});

test("cada usuario administra únicamente sus tokens push", async () => {
  const owner = environment
    .authenticatedContext("owner", {email_verified: true})
    .firestore();
  const member = environment
    .authenticatedContext("member", {email_verified: true})
    .firestore();
  const device = {
    token: "token-fcm-de-prueba-con-longitud-suficiente",
    platform: "android",
    updatedAt: Timestamp.now(),
  };

  await assertSucceeds(setDoc(doc(owner, "users/owner/devices/device-1"), device));
  await assertFails(setDoc(doc(member, "users/owner/devices/device-2"), device));
});

test("permite recurrencias cifradas y bloquea al lector", async () => {
  const member = environment
    .authenticatedContext("member", {email_verified: true})
    .firestore();
  const junior = environment
    .authenticatedContext("junior", {email_verified: true})
    .firestore();
  const recurring = {
    schemaVersion: 1,
    frequency: "monthly",
    nextDueAt: Timestamp.now(),
    active: true,
    confirmBeforePosting: true,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    createdBy: "member",
    payload: cipher,
  };

  await assertSucceeds(
    setDoc(doc(member, "households/home/recurring/monthly"), recurring),
  );
  await assertFails(
    setDoc(doc(junior, "households/home/recurring/blocked"), {
      ...recurring,
      createdBy: "junior",
    }),
  );
});

test("protege las categorías personalizadas con el mismo cifrado", async () => {
  const member = environment
    .authenticatedContext("member", {email_verified: true})
    .firestore();
  const base = {
    schemaVersion: 1,
    type: "expense",
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    createdBy: "member",
  };

  await assertSucceeds(
    setDoc(doc(member, "households/home/categories/pets"), {
      ...base,
      payload: cipher,
    }),
  );
  await assertFails(
    setDoc(doc(member, "households/home/categories/plain"), {
      ...base,
      payload: {name: "Mascotas"},
    }),
  );
});
