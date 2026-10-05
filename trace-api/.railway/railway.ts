import { defineRailway, github, preserve, project, service, volume } from "railway/iac";

// This repo manages only the `api` service; the `postgis` database is managed in Railway.
// See https://docs.railway.com/infrastructure-as-code#multi-repo-projects
export const partial = "api";

export default defineRailway(() => {
  // Pinned to what exists, so a plan never moves or resizes the media volume.
  const media = volume("api-volume", { region: "sfo", sizeMB: 5000 });
  const api = service("api", {
    // Every push to main that touches trace-api/ builds trace-api/Dockerfile and deploys.
    source: github("ehtisham-badar/placeees", { branch: "main", rootDirectory: "trace-api" }),
    build: { watchPatterns: ["trace-api/**"] },
    deploy: {
      healthcheckPath: "/health",
      healthcheckTimeout: 60,
      restartPolicyType: "ON_FAILURE",
      restartPolicyMaxRetries: 5,
    },
    // Photos and voice until Cloudflare R2 is set up.
    volumeMounts: { "/data": media },
    variables: {
      // Secrets live only in Railway; preserve() keeps whatever is set there.
      DATABASE_URL: preserve(),
      JWT_SECRET: preserve(),
      ADMIN_TOKEN: preserve(),
      DEV_LOGIN_CODE: preserve(),
      FCM_CLIENT_EMAIL: preserve(),
      FCM_PRIVATE_KEY: preserve(),
      // Plain settings, versioned here.
      // Off in production: Google sign-in is live. Local testing sets it in its own env.
      ALLOW_DEV_LOGIN: "false",
      INTEGRITY_MODE: "off",
      RUN_JOBS: "true",
      LOG_LEVEL: "info",
      LOCAL_MEDIA_DIR: "/data/media",
      PUBLIC_API_URL: "https://api-production-c9db.up.railway.app",
      PUBLIC_WEB_URL: "https://api-production-c9db.up.railway.app",
      // Google sign-in: ID tokens must be issued for the Firebase project's web OAuth client.
      GOOGLE_CLIENT_IDS: "885459685841-d7tmn8t53ahq7eaha09oouob7m38bao6.apps.googleusercontent.com",
      // FCM push (Firebase project trace-app-5f40f); the service-account key is set only in Railway.
      FCM_PROJECT_ID: "trace-app-5f40f",
      // Volumes are root-owned; the image's non-root user couldn't write to /data.
      RAILWAY_RUN_UID: "0",
    },
  });
  return project("trace", {
    resources: [api, media],
  });
});
