const fs = require("node:fs");
const path = require("node:path");
const {after, before, beforeEach, test} = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
} = require("firebase/firestore");

const projectId = "homewallet-rules-test";
let environment;

const cipher = {
  v: 1,
  alg: "A256GCM",
  ct: "encrypted-content",
  iv: "123456789012",
  tag: "1234567890123456",
};

function userDb(uid) {
  return environment
    .authenticatedContext(uid, {email_verified: true})
    .firestore();
}

async function seedSpace({
  householdId,
  kind,
  members,
}) {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "households", householdId), {
      kind,
      memberCount: members.length,
      createdBy: members[0].uid,
      createdAt: new Date(),
      updatedAt: new Date(),
      keyVersion: 1,
      privatePayload: cipher,
    });
    for (const member of members) {
      await setDoc(doc(db, "households", householdId, "members", member.uid), {
        uid: member.uid,
        role: member.role,
        status: "active",
        joinedAt: new Date(),
        privatePayload: cipher,
      });
    }
  });
}

async function seedUser(uid, householdIds, activeHouseholdId) {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users", uid), {
      displayName: uid,
      phoneNumber: "",
      photoUrl: null,
      activeHouseholdId,
      householdIds,
      createdAt: new Date(),
      updatedAt: new Date(),
      termsVersion: "2026-08-02",
      termsAcceptedAt: new Date(),
      onboardingCompleted: true,
      onboardingCompletedAt: new Date(),
      preferredCategories: [],
    });
  });
}

function transactionDocument(uid) {
  return {
    schemaVersion: 1,
    type: "expense",
    occurredAt: new Date("2025-01-15T12:00:00Z"),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy: uid,
    payload: cipher,
  };
}

function sharedExpenseDocument(uid) {
  return {
    schemaVersion: 1,
    occurredAt: new Date("2025-01-15T12:00:00Z"),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy: uid,
    payload: cipher,
  };
}

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: 8080,
      rules: fs.readFileSync(
        path.resolve(__dirname, "..", "..", "firestore.rules"),
        "utf8",
      ),
    },
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
});

after(async () => {
  await environment.cleanup();
});

test("members can access only the financial data of their own space", async () => {
  await seedSpace({
    householdId: "personal",
    kind: "individual",
    members: [{uid: "nayah", role: "owner"}],
  });
  await seedSpace({
    householdId: "other-group",
    kind: "group",
    members: [{uid: "another-user", role: "owner"}],
  });

  const db = userDb("nayah");
  await assertSucceeds(
    setDoc(
      doc(db, "households", "personal", "transactions", "own-record"),
      transactionDocument("nayah"),
    ),
  );
  await assertFails(
    getDoc(doc(db, "households", "other-group", "transactions", "record")),
  );
});

test("Individual rejects bill splits while shared spaces allow them", async () => {
  await seedSpace({
    householdId: "personal",
    kind: "individual",
    members: [{uid: "nayah", role: "owner"}],
  });
  await seedSpace({
    householdId: "trip",
    kind: "group",
    members: [{uid: "nayah", role: "owner"}],
  });

  const db = userDb("nayah");
  await assertFails(
    setDoc(
      doc(db, "households", "personal", "sharedExpenses", "invalid"),
      sharedExpenseDocument("nayah"),
    ),
  );
  await assertSucceeds(
    setDoc(
      doc(db, "households", "trip", "sharedExpenses", "valid"),
      sharedExpenseDocument("nayah"),
    ),
  );
});

test("a junior can read but cannot create financial information", async () => {
  await seedSpace({
    householdId: "family",
    kind: "family",
    members: [
      {uid: "owner", role: "owner"},
      {uid: "junior", role: "junior"},
    ],
  });
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), "households", "family", "transactions", "seed"),
      {
        ...transactionDocument("owner"),
        createdAt: new Date(),
        updatedAt: new Date(),
      },
    );
  });

  const db = userDb("junior");
  await assertSucceeds(
    getDoc(doc(db, "households", "family", "transactions", "seed")),
  );
  await assertFails(
    setDoc(
      doc(db, "households", "family", "transactions", "blocked"),
      transactionDocument("junior"),
    ),
  );
});

test("the active space can only be changed to an active membership", async () => {
  await seedSpace({
    householdId: "personal",
    kind: "individual",
    members: [{uid: "nayah", role: "owner"}],
  });
  await seedSpace({
    householdId: "trip",
    kind: "group",
    members: [{uid: "nayah", role: "member"}],
  });
  await seedUser("nayah", ["personal", "trip"], "personal");

  const user = doc(userDb("nayah"), "users", "nayah");
  await assertSucceeds(
    updateDoc(user, {
      activeHouseholdId: "trip",
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(user, {
      activeHouseholdId: "unknown-space",
      updatedAt: serverTimestamp(),
    }),
  );
});

test("key recovery backups cannot be read or written directly", async () => {
  await seedSpace({
    householdId: "protected-space",
    kind: "group",
    members: [{uid: "owner", role: "owner"}],
  });
  const backup = doc(
    userDb("owner"),
    "internalHouseholdKeyBackups",
    "protected-space",
  );
  await assertFails(getDoc(backup));
  await assertFails(setDoc(backup, cipher));
});

test("members update only their own encrypted profile and contributors set income", async () => {
  await seedSpace({
    householdId: "income-space",
    kind: "family",
    members: [
      {uid: "owner", role: "owner"},
      {uid: "partner", role: "member"},
      {uid: "junior", role: "junior"},
    ],
  });
  const db = userDb("partner");
  await assertSucceeds(
    updateDoc(doc(db, "households", "income-space", "members", "partner"), {
      privatePayload: {...cipher, ct: "updated-encrypted-profile"},
    }),
  );
  await assertSucceeds(
    updateDoc(doc(db, "households", "income-space", "members", "partner"), {
      incomePayload: {...cipher, ct: "encrypted-monthly-income"},
    }),
  );
  await assertFails(
    updateDoc(doc(db, "households", "income-space", "members", "owner"), {
      privatePayload: {...cipher, ct: "unauthorized-update"},
    }),
  );
  await assertFails(
    updateDoc(
      doc(userDb("junior"), "households", "income-space", "members", "junior"),
      {incomePayload: {...cipher, ct: "junior-income-update"}},
    ),
  );
});
