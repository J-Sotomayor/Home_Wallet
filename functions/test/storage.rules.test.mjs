import {readFileSync} from "node:fs";
import {after, beforeEach, test} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {getBytes, ref, uploadBytes} from "firebase/storage";

const [host = "127.0.0.1", portText = "9199"] =
  (process.env.FIREBASE_STORAGE_EMULATOR_HOST ?? "127.0.0.1:9199").split(":");

const environment = await initializeTestEnvironment({
  projectId: "homewallet-prod",
  storage: {
    host,
    port: Number(portText),
    rules: readFileSync(new URL("../../storage.rules", import.meta.url), "utf8"),
  },
});

beforeEach(async () => environment.clearStorage());
after(async () => environment.cleanup());

const image = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);

test("la foto de perfil solo puede leerla y escribirla su propietario", async () => {
  const owner = environment.authenticatedContext("owner").storage();
  const other = environment.authenticatedContext("other").storage();
  const avatar = ref(owner, "profilePhotos/owner/avatar");

  await assertSucceeds(uploadBytes(avatar, image, {contentType: "image/png"}));
  await assertSucceeds(getBytes(avatar));
  await assertFails(getBytes(ref(other, "profilePhotos/owner/avatar")));
});

test("rechaza nombres y tipos de archivo no autorizados", async () => {
  const owner = environment.authenticatedContext("owner").storage();

  await assertFails(
    uploadBytes(ref(owner, "profilePhotos/owner/otro"), image, {
      contentType: "image/png",
    }),
  );
  await assertFails(
    uploadBytes(ref(owner, "profilePhotos/owner/avatar"), image, {
      contentType: "image/svg+xml",
    }),
  );
});
