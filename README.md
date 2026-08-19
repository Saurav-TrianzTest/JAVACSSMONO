# dashboard-app

CSS containerization (CZ) test fixture. Each cz-css-* rule (1000-1017) is triggered at least once, except cz-css-1007 — see note below.

## Structure

Enterprise Java application at the repo root, with the CSS fixture assets living
alongside it in a clearly separated frontend directory.

```
dashboard-app/
├── pom.xml                                     single Maven project, inherits spring-boot-starter-parent
├── src/main/java/com/trianz/dashboard/
│   ├── DashboardApplication.java                entry point (@SpringBootApplication)
│   ├── controller/HealthController.java         REST layer
│   └── service/HealthService.java               business logic layer
├── src/main/resources/application.properties
├── src/test/java/.../HealthControllerTest.java  MockMvc test
├── frontend/components/Card.js                  frontend CSS-in-JS component (moved out of src/)
├── assets/styles/, styles/                      CSS rule fixture files
└── Dockerfile
```

## Build, run, test

```
mvn spring-boot:run          # run directly
mvn package                  # build target/dashboard-app-1.0.0.jar
mvn test                     # run HealthControllerTest
```

Exposes `GET /api/health` on port 8080.

## Maven Wrapper

`.mvn/wrapper/maven-wrapper.properties` is included; generate `mvnw` / `mvnw.cmd` locally with:

```
mvn wrapper:wrapper
```

## Note on cz-css-1007 (CSS-in-JS Without SSR Extract)

`Card.js` was previously located at `src/components/Card.js` to trigger this rule. It has
been moved to `frontend/components/Card.js` so that `src/` is unambiguously a Java source
tree, matching a proper enterprise Java project layout. **This means cz-css-1007 will no
longer fire at its old path** — this trade-off was made intentionally to prioritize a clean,
recognizable Java application structure. If cz-css-1007 coverage is needed again, re-add a
CSS-in-JS trigger file under `frontend/` and update the TRUTH document accordingly.

## Note on cz-css-1009 (Unminified HTML/CSS)

This rule fires on nearly every line of non-minified source by design — a per-line style
heuristic, not a single-site trigger. Left as-is; minifying would defeat the fixture's readability.
