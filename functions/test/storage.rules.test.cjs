const fs = require("node:fs");
const path = require("node:path");
const {after, before, beforeEach, test} = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {getBytes, ref, uploadBytes} = require("firebase/storage");

const projectId = "homewallet-storage-rules-test";
let environment;

function userStorage(uid) {
  return environment.authenticatedContext(uid).storage();
}

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    storage: {
      host: "127.0.0.1",
      port: 9199,
      rules: fs.readFileSync(
        path.resolve(__dirname, "..", "..", "storage.rules"),
        "utf8",
      ),
    },
  });
});

beforeEach(async () => {
  await environment.clearStorage();
});

after(async () => {
  await environment.cleanup();
});

test("a user uploads and reads their valid profile image", async () => {
  const avatar = ref(userStorage("alice"), "profilePhotos/alice/avatar");
  await assertSucceeds(
    uploadBytes(avatar, new Uint8Array([1, 2, 3]), {
      contentType: "image/png",
    }),
  );
  await assertSucceeds(getBytes(avatar));
});

test("another user cannot read or overwrite a private profile image", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(
      ref(context.storage(), "profilePhotos/alice/avatar"),
      new Uint8Array([1, 2, 3]),
      {contentType: "image/jpeg"},
    );
  });
  const foreignAvatar = ref(
    userStorage("bob"),
    "profilePhotos/alice/avatar",
  );
  await assertFails(getBytes(foreignAvatar));
  await assertFails(
    uploadBytes(foreignAvatar, new Uint8Array([4]), {
      contentType: "image/png",
    }),
  );
});

test("profile writes reject an invalid file name or content type", async () => {
  const storage = userStorage("alice");
  await assertFails(
    uploadBytes(
      ref(storage, "profilePhotos/alice/not-avatar"),
      new Uint8Array([1]),
      {contentType: "image/png"},
    ),
  );
  await assertFails(
    uploadBytes(
      ref(storage, "profilePhotos/alice/avatar"),
      new Uint8Array([1]),
      {contentType: "application/pdf"},
    ),
  );
});

test("profile writes reject files at or above five MiB", async () => {
  const avatar = ref(userStorage("alice"), "profilePhotos/alice/avatar");
  await assertFails(
    uploadBytes(avatar, new Uint8Array(5 * 1024 * 1024), {
      contentType: "image/webp",
    }),
  );
});

test("all storage paths outside profile photos remain denied", async () => {
  const otherPath = ref(userStorage("alice"), "exports/alice/data.csv");
  await assertFails(
    uploadBytes(otherPath, new Uint8Array([1, 2]), {
      contentType: "text/csv",
    }),
  );
  await assertFails(getBytes(otherPath));
});
