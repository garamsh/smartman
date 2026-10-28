import { readPhoto } from "./actions";
import type { Extraction } from "./read-photo";

/** Prepares one bounded upload; stopping leaves an in-flight server request counted but saves nothing. */
export async function extractPhoto(file: File, signal: AbortSignal): Promise<Extraction> {
  if (file.size > 6 * 1024 * 1024) return { message: "사진은 6MB 이하로 골라 주세요" };
  try {
    signal.throwIfAborted();
    const upload = file.size <= 3 * 1024 * 1024 ? file : await preparePhoto(file);
    if (!upload) return { message: "사진을 줄이지 못했어요. 다른 사진을 골라 주세요." };
    const form = new FormData();
    form.set("photo", upload);
    const result = await readPhoto(form);
    return signal.aborted
      ? { message: "사진 읽기를 멈췄어요. 이미 시작한 사진은 한도에 포함될 수 있어요." }
      : result;
  } catch {
    return { message: "사진을 읽지 못했어요. 다시 시도해 주세요." };
  }
}
async function preparePhoto(file: File): Promise<File | null> {
  const image = await createImageBitmap(file);
  try {
    const ratio = Math.min(1, 2048 / Math.max(image.width, image.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(image.width * ratio));
    canvas.height = Math.max(1, Math.round(image.height * ratio));
    const context = canvas.getContext("2d");
    if (!context) return null;
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    for (const quality of [0.85, 0.7, 0.55, 0.4]) {
      const blob = await new Promise<Blob | null>((resolve) => {
        canvas.toBlob(resolve, "image/jpeg", quality);
      });
      if (blob && blob.size <= 3 * 1024 * 1024)
        return new File([blob], "photo.jpg", { type: "image/jpeg" });
    }
    return null;
  } finally {
    image.close();
  }
}
