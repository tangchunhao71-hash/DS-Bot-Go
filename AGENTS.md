# DS Bot Go repository rules

- This is an independent derivative. Preserve upstream copyright, license and NOTICE files. The mobile client is AGPL-3.0; separately identified original artwork/tools and independent components retain their own licenses.
- Read the component's own development and verification rules before editing it.
- Accept Issues. Do not merge external pull requests. Only the repository owner's internal PRs may proceed; do not execute external PR code from a privileged workflow.
- Never commit credentials, signing keys, runtime state, user chats, local profiles, diagnostic logs or build caches.
- Keep APKs and matching corresponding-source archives together at one fixed release commit. Changes to code or build inputs invalidate an earlier source-to-APK receipt.
- Preserve the Android package/signing identity appropriate to the release. Do not uninstall a user's app or touch their live desktop profile to test a source change.
- Use the smallest checks that cover the change; obey any component-required checks. Report skipped or unperformed device checks truthfully.
