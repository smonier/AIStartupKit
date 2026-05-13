---
paths:
  - "**/src/main/java/**"
  - "**/pom.xml"
  - "**/*.java"
  - "**/src/main/resources/OSGI-INF/**"
---

# OSGi & Maven Rules

Auto-loaded when touching Java source or Maven files. Full reference: `.agents/context/jahia-platform.md`.

## Maven Module Invariants

- Parent POM must declare `<packaging>bundle</packaging>` and reference `org.jahia.modules:jahia-modules` or `jahia-default-modules-parent`.
- Bundle symbolic name = Maven `artifactId`. Keep it unique across all deployed bundles.
- Never shade/repackage Jahia platform dependencies — use `<scope>provided</scope>`.
- Use `maven-bundle-plugin` for OSGi manifest generation. Do not hand-edit `MANIFEST.MF`.
- Run `mvn clean install` to build. The `.jar` lands in `target/` and can be hot-deployed.

## OSGi Declarative Services

- Annotate with `@Component(service = MyService.class)` for singleton components.
- Use `@Reference` for injection — never use `BundleContext.getServiceReference()` manually.
- Never store `@Reference`d services in static fields — breaks bundle lifecycle.
- Implement `@Activate` / `@Deactivate` for init/cleanup. Do not use constructors for OSGi init.
- Use `@Reference(policy = ReferencePolicy.DYNAMIC, policyOption = ReferencePolicyOption.GREEDY)` for optional services.

## Service Design Rules (CTO standard)

- Separate business logic from API layer — services must not know about HTTP/GraphQL.
- Reuse platform infrastructure: `TaggingService`, `JahiaCacheManager`, `JahiaPaginationHelper`.
- Batch operations must return counts + paths, not full node objects.
- Every public service class and method needs Javadoc: role, threading model, params, return, throws.
- Services are singletons — never store per-request or per-user state in fields.

## Deployment

```bash
mvn clean install        # builds the .jar
# Copy to Jahia's deploy folder, or use:
curl -u root:root -F "bundle=@target/<artifact>.jar" http://localhost:8080/modules/api/bundles
```

Hot-deploy works when `jahia.auto.deploy=true` in `jahia.node.properties`.
