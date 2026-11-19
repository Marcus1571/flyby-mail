# findings — FlyBy for Mail

Append-only log. Newest first.

## 2026-11-19 — Mail ignores an extension that does not declare its capabilities

- Symptom: `pluginkit -m -p com.apple.email.extension` listed the signed extension (even elected with `+`), but Mail ▸ Settings ▸
  Extensions said "No Extensions".
- Cause: the Info.plist had no `NSExtension ▸ NSExtensionAttributes ▸ MEExtensionCapabilities` array. Xcode's Mail Extension template
  (`Mail Extension.xctemplate/TemplateInfo.plist` in Xcode.app) puts `MEComposeSessionHandler` (and the other chosen handlers) there;
  `MEComposeSession` (icon = SF Symbol name, tooltip) sits in the same `NSExtensionAttributes`.
- Lesson: pluginkit registration is not proof that Mail lists the extension; check Mail's Extensions pane.
