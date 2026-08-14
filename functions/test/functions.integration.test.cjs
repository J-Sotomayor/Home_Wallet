const {after, test} = require("node:test");
const assert = require("node:assert/strict");
const {
  deleteApp: deleteClientApp,
  initializeApp: initializeClientApp,
} = require("firebase/app");
const {
  connectAuthEmulator,
  createUserWithEmailAndPassword,
  getAuth: getClientAuth,
} = require("firebase/auth");
const {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} = require("firebase/functions");
const {
  deleteApp: deleteAdminApp,
  initializeApp: initializeAdminApp,
} = require("firebase-admin/app");
const {getAuth: getAdminAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");

const projectId = "homewallet-prod";
const clientApp = initializeClientApp({
  projectId,
  apiKey: "fake-api-key",
  appId: "1:123456789:android:test",
});
const adminApp = initializeAdminApp({projectId}, "integration-tests");
const adminAuth = getAdminAuth(adminApp);
const db = getFirestore(adminApp);
const auth = getClientAuth(clientApp);
connectAuthEmulator(auth, "http://127.0.0.1:9099", {disableWarnings: true});
const functions = getFunctions(clientApp, "southamerica-west1");
connectFunctionsEmulator(functions, "127.0.0.1", 5001);

let sequence = 0;

async function verifiedUser(label) {
  sequence += 1;
  const credential = await createUserWithEmailAndPassword(
    auth,
    `${label}-${sequence}@example.test`,
    "HomeWallet1234",
  );
  await adminAuth.updateUser(credential.user.uid, {emailVerified: true});
  await credential.user.reload();
  await credential.user.getIdToken(true);
  await db.collection("users").doc(credential.user.uid).set({
    displayName: label,
    phoneNumber: "",
    photoUrl: null,
    activeHouseholdId: null,
    householdIds: [],
    createdAt: new Date(),
    updatedAt: new Date(),
    termsVersion: "2026-08-02",
    termsAcceptedAt: new Date(),
    onboardingCompleted: true,
    onboardingCompletedAt: new Date(),
    preferredCategories: [],
  });
  return credential.user;
}

async function clearRateLimit(uid, action) {
  await db.collection("internalRateLimits").doc(`${uid}_${action}`).delete();
}

async function callAs(user, name, data) {
  await auth.updateCurrentUser(user);
  await user.getIdToken(true);
  return httpsCallable(functions, name)(data);
}

async function callWithToken(token, name, data) {
  const response = await fetch(
    `http://127.0.0.1:5001/${projectId}/southamerica-west1/${name}`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({data}),
    },
  );
  const body = await response.json();
  if (!response.ok || body.error) {
    const error = new Error(body.error?.message ?? "Callable request failed");
    error.code = body.error?.status;
    throw error;
  }
  return body.result;
}

async function createSpace(user, kind) {
  await clearRateLimit(user.uid, "createHousehold");
  const result = await callAs(user, "createHousehold", {kind});
  return result.data.householdId;
}

after(async () => {
  await deleteClientApp(clientApp);
  await deleteAdminApp(adminApp);
});

test("one account can own only one Individual but more than five total spaces", async () => {
  const user = await verifiedUser("multi-space-owner");
  const individualId = await createSpace(user, "individual");

  await clearRateLimit(user.uid, "createHousehold");
  await assert.rejects(
    () => callAs(user, "createHousehold", {kind: "individual"}),
    (error) => error.code === "functions/already-exists",
  );

  for (let index = 0; index < 5; index += 1) {
    await createSpace(user, index % 2 === 0 ? "group" : "family");
  }
  const profile = (await db.collection("users").doc(user.uid).get()).data();
  assert.equal(profile.individualHouseholdId, individualId);
  assert.equal(profile.householdIds.length, 6);
});

test("the inviter fixes the Family role and can explicitly revoke the invitation", async () => {
  const owner = await verifiedUser("family-owner");
  const junior = await verifiedUser("family-junior");
  const revokedCandidate = await verifiedUser("family-revoked");
  const familyId = await createSpace(owner, "family");
  const invitation = await callAs(owner, "createInvitation", {
    householdId: familyId,
    role: "junior",
  });
  assert.equal(invitation.data.role, "junior");
  assert.equal(
    (await db.collection("invitations").doc(familyId).get()).data().role,
    "junior",
  );

  await callAs(junior, "acceptInvitation", {
    invitationId: invitation.data.invitationId,
    token: invitation.data.token,
  });
  assert.equal(
    (
      await db
        .collection("households")
        .doc(familyId)
        .collection("members")
        .doc(junior.uid)
        .get()
    ).data().role,
    "junior",
  );

  await clearRateLimit(owner.uid, "createInvitation");
  const revokedInvitation = await callAs(owner, "createInvitation", {
    householdId: familyId,
    role: "member",
  });
  await callAs(owner, "revokeInvitation", {householdId: familyId});
  assert.equal(
    (await db.collection("invitations").doc(familyId).get()).data().status,
    "revoked",
  );
  await assert.rejects(
    () =>
      callAs(revokedCandidate, "acceptInvitation", {
        invitationId: revokedInvitation.data.invitationId,
        token: revokedInvitation.data.token,
      }),
    (error) => error.code === "functions/failed-precondition",
  );
});

test("concurrent acceptance cannot add a third person to Pareja", async () => {
  const owner = await verifiedUser("couple-owner");
  const firstCandidate = await verifiedUser("couple-first");
  const secondCandidate = await verifiedUser("couple-second");
  const coupleId = await createSpace(owner, "couple");
  const invitation = await callAs(owner, "createInvitation", {
    householdId: coupleId,
    role: "member",
  });
  const payload = {
    invitationId: invitation.data.invitationId,
    token: invitation.data.token,
  };
  const [firstToken, secondToken] = await Promise.all([
    firstCandidate.getIdToken(true),
    secondCandidate.getIdToken(true),
  ]);

  const attempts = await Promise.allSettled([
    callWithToken(firstToken, "acceptInvitation", payload),
    callWithToken(secondToken, "acceptInvitation", payload),
  ]);
  assert.equal(
    attempts.filter((attempt) => attempt.status === "fulfilled").length,
    1,
  );
  assert.equal(
    (await db.collection("households").doc(coupleId).get()).data().memberCount,
    2,
  );
  const members = await db
    .collection("households")
    .doc(coupleId)
    .collection("members")
    .where("status", "==", "active")
    .get();
  assert.equal(members.size, 2);

  await clearRateLimit(owner.uid, "createInvitation");
  await assert.rejects(
    () => callAs(owner, "createInvitation", {householdId: coupleId}),
    (error) => error.code === "functions/resource-exhausted",
  );
});

test("joining a shared space preserves all previous memberships", async () => {
  const owner = await verifiedUser("group-owner");
  const guest = await verifiedUser("group-guest");
  const guestIndividualId = await createSpace(guest, "individual");
  const groupId = await createSpace(owner, "group");
  const invitation = await callAs(owner, "createInvitation", {
    householdId: groupId,
    role: "member",
  });

  await callAs(guest, "acceptInvitation", {
    invitationId: invitation.data.invitationId,
    token: invitation.data.token,
  });
  const profile = (await db.collection("users").doc(guest.uid).get()).data();
  assert.deepEqual(
    new Set(profile.householdIds),
    new Set([guestIndividualId, groupId]),
  );
});
