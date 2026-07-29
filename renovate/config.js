module.exports = {
  platform: "gitea",
  endpoint: "https://gitea.josephbernal.com/api/v1/",
  token: process.env.RENOVATE_TOKEN,
  gitUrl: "endpoint",
  autodiscover: false,
  repositories: [
    "joe/Bernal-labs-infra",
    "joe/futbol-modelo",
    "joe/Sunshine_Ledger",
    "joe/josephbernal-site"
  ],
  onboarding: true,
  onboardingConfig: {
    extends: ["config:recommended"]
  }
};
