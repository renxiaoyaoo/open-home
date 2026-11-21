declare namespace Cloudflare {
  interface Env {
    DB?: D1Database;
    BUCKET?: R2Bucket;
    OPENHOME_PUBLIC_API_URL?: string;
  }
}
