export function isNativeAPIOrigin(requestURL: string, publicAPIURL: string | undefined) {
  return Boolean(publicAPIURL && new URL(requestURL).origin === new URL(publicAPIURL).origin);
}
