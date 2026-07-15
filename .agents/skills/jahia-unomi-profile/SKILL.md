---
name: jahia-unomi-profile
description: Read and update jCustomer (Apache Unomi 3.x) profile properties from a Jahia JavaScript module — client-side fetch via jExperience proxy, browser-side update via window.wem, property type definitions, jCustomer rule files, server-side OSGi profile queries, and thirdparty security model.
allowed-tools: Bash, Read, Write, Edit
---

# Skill: jahia-unomi-profile

Everything needed to read and write jCustomer profile properties from a Jahia JS module or OSGi bundle.

---

## Architecture overview

```
Browser (client island)
  └── window.wem.collectEvent()         ← jExperience tracker (handles auth)
        └── POST context.json           ← event type must NOT be thirdparty-restricted
              └── jCustomer rule        ← eventTypeCondition → updatePropertiesAction

Browser (client island)
  └── POST /modules/jexperience/proxy/{siteKey}/context.json   ← READ profile
        └── requiredProfileProperties: [...]
              └── returns profileProperties map

OSGi job / service
  └── ContextServerService.executePostRequest()   ← server-to-server, auth handled internally
        └── POST /cxs/profiles/search             ← query profiles
        └── POST /cxs/eventcollector              ← send events server-side
```

---

## Part 1 — Reading profile properties (client-side)

Fetch properties by POSTing to the jExperience proxy. Auth comes from the visitor's session cookie — no credentials needed.

```typescript
// In a .client.tsx island

declare global {
  interface Window {
    cxs?: { sessionId?: string };
    digitalData?: { page?: { pageInfo?: { pageID?: string } }; scope?: string };
    contextJsParameters?: { siteKey?: string; contextPath?: string };
  }
}

const getCookie = (name: string): string | null => {
  const m = document.cookie.match(new RegExp(`(^| )${name}=([^;]+)`));
  return m ? decodeURIComponent(m[2]) : null;
};

const getSessionId = () =>
  window.cxs?.sessionId ?? getCookie("wem-session-id");

const getProxyBase = (siteKey: string) =>
  `${window.location.origin}/modules/jexperience/proxy/${siteKey}`;

// Fetch profile
const response = await fetch(`${getProxyBase(siteKey)}/context.json`, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Accept": "application/json",
    "Site-Key": siteKey,
  },
  credentials: "include",
  body: JSON.stringify({
    sessionId: getSessionId(),
    requiredProfileProperties: [
      "firstName", "lastName", "email", "company",
      "MySopraHR_Solution", "MySopraHR_Version",
      "MySopraHR_NotifEnabled", "MySopraHR_NotifFrequency",
      "MySopraHR_NotifCategories",  // multivalued → returns string[]
    ],
    source: {
      itemId: window.location.pathname,
      itemType: "page",
      scope: siteKey,
    },
  }),
});

const data = await response.json();
const props = data.profileProperties ?? {};
// props.firstName, props.MySopraHR_Solution, etc.

// Multivalued property comes back as string[]:
const cats: string[] = Array.isArray(props.MySopraHR_NotifCategories)
  ? props.MySopraHR_NotifCategories
  : [];
```

### Server view passes siteKey to the island

```tsx
// default.server.tsx
jahiaComponent({ componentType: "view", nodeType: "shr:profileManager", ... },
  (_props, { renderContext }) => {
    const { renderContext: ctx } = useServerContext();
    const siteKey = (ctx.getSite() as unknown as JCRNodeWrapper).getName();
    const isEditMode = ctx.isEditMode();

    return <Island component={ProfileManager} props={{ siteKey, isEditMode }} />;
  }
);
```

---

## Part 2 — Updating profile properties (client-side)

### The security model (critical)

Unomi 3 has a thirdparty event allowlist in `/opt/jcustomer/etc/org.apache.unomi.thirdparty.cfg`:

```properties
thirdparty.provider1.key=670c26d1cc413346c3b2fd9ce65dab41
thirdparty.provider1.ipAddresses=127.0.0.1,::1,172.19.0.2   # add Jahia's Docker IP!
thirdparty.provider1.allowedEvents=login,updateProperties
```

**If an event type is in `allowedEvents` → it is ONLY accepted from a trusted IP with the `X-Unomi-Peer` key.**
- `updateProperties` is restricted — DO NOT use it from the browser.
- Custom event types NOT in any allowedEvents list → accepted from anyone (public).

### Correct pattern: custom event type + jCustomer rule

**Step 1 — Use `window.wem.collectEvent` with a PUBLIC event type:**

```typescript
declare global {
  interface Window {
    wem?: {
      buildEvent: (type: string, target: Record<string, unknown>, source: Record<string, unknown>) => Record<string, unknown>;
      buildTarget: (id: string, type: string) => Record<string, unknown>;
      buildSource: (id: string, type: string) => Record<string, unknown>;
      collectEvent: (event: Record<string, unknown>, onSuccess?: () => void, onError?: () => void) => void;
    };
  }
}

if (!window.wem) {
  // wem not injected — jExperience not configured for this site
  return;
}

const event = window.wem.buildEvent(
  "updateUserEfficyPortalData",           // public event type — NOT thirdparty-restricted
  window.wem.buildTarget("MySopraHR_NotifEnabled", "user-property"),
  window.wem.buildSource(siteKey, "site"),
);

// Payload: keys prefixed with "properties." target jCustomer profile properties
(event as Record<string, unknown>).properties = {
  update: {
    "properties.MySopraHR_NotifEnabled":    "true",
    "properties.MySopraHR_NotifFrequency":  "weekly:MONDAY",
    "properties.MySopraHR_NotifCategories": ["uuid1", "uuid2"],  // array for multivalued
  },
};

await new Promise<void>((resolve) => {
  window.wem!.collectEvent(event, resolve, resolve);
});
```

**Why `updateUserEfficyPortalData`?**
- It is a public event type already deployed across Jahia instances with the Efficy portal module
- Its jCustomer rule fires `updatePropertiesAction` which reads `event.properties.update`
- No thirdparty restriction → works from the browser

---

## Part 3 — jCustomer property type definitions

Create JSON files in `settings/jexperience/properties/`. Jahia deploys them to jCustomer on module install.

### String property

```json
{
  "itemId": "MySopraHR_NotifFrequency",
  "itemType": "propertyType",
  "version": 1,
  "target": "profiles",
  "dateRanges": [],
  "numericRanges": [],
  "ipRanges": [],
  "automaticMappingsFrom": [],
  "multivalued": false,
  "childPropertyTypes": [],
  "metadata": {
    "id": "MySopraHR_NotifFrequency",
    "name": "MySopraHR_NotifFrequency",
    "tags": [],
    "systemTags": [],
    "enabled": true,
    "missingPlugins": false,
    "hidden": false,
    "readOnly": false
  },
  "type": "string"
}
```

### Boolean property

```json
{
  "itemId": "MySopraHR_NotifEnabled",
  "itemType": "propertyType",
  "version": 1,
  "target": "profiles",
  "dateRanges": [],
  "numericRanges": [],
  "ipRanges": [],
  "automaticMappingsFrom": [],
  "multivalued": false,
  "childPropertyTypes": [],
  "metadata": {
    "id": "MySopraHR_NotifEnabled",
    "name": "MySopraHR_NotifEnabled",
    "tags": [],
    "systemTags": [],
    "enabled": true,
    "missingPlugins": false,
    "hidden": false,
    "readOnly": false
  },
  "type": "boolean"
}
```

### Multivalued string property

```json
{
  "itemId": "MySopraHR_NotifCategories",
  "itemType": "propertyType",
  "version": 1,
  "target": "profiles",
  "dateRanges": [],
  "numericRanges": [],
  "ipRanges": [],
  "automaticMappingsFrom": [],
  "multivalued": true,
  "childPropertyTypes": [],
  "metadata": {
    "id": "MySopraHR_NotifCategories",
    "name": "MySopraHR_NotifCategories",
    "tags": [],
    "systemTags": [],
    "enabled": true,
    "missingPlugins": false,
    "hidden": false,
    "readOnly": false
  },
  "type": "string"
}
```

**Available types:** `string`, `boolean`, `integer`, `long`, `float`, `date`, `set`, `identifier`

---

## Part 4 — jCustomer rule definitions

Create JSON files in `settings/jexperience/rules/`. Deployed to jCustomer on module install.

### Rule: listen for custom event → update profile properties

```json
{
  "itemId": "mysoprahrNotifUpdate",
  "itemType": "rule",
  "version": 1,
  "condition": {
    "type": "eventTypeCondition",
    "parameterValues": {
      "eventTypeId": "updateUserEfficyPortalData"
    }
  },
  "actions": [
    {
      "type": "updatePropertiesAction",
      "parameterValues": {}
    }
  ],
  "raiseEventOnlyOnceForProfile": false,
  "raiseEventOnlyOnceForSession": false,
  "raiseEventOnlyOnce": false,
  "priority": 0,
  "metadata": {
    "id": "mysoprahrNotifUpdate",
    "name": "MySopraHR - Update notification preferences",
    "description": "Fires updatePropertiesAction when a visitor saves notification preferences",
    "scope": "mysoprahr",
    "tags": [],
    "systemTags": [],
    "enabled": true,
    "missingPlugins": false,
    "hidden": false,
    "readOnly": false
  }
}
```

### How `updatePropertiesAction` reads the event payload

```json
{
  "properties": {
    "update": {
      "properties.myProperty":  "value",           // single value
      "properties.myMultival":  ["val1", "val2"]   // multivalued
    }
  }
}
```

The `properties.` prefix tells the action to write to the **profile** property namespace.

---

## Part 5 — Server-side profile query (OSGi)

Use `ContextServerService.executePostRequest()`. Auth to jCustomer is handled internally by jExperience — no credentials to manage.

```java
// Interface: org.jahia.modules.jexperience.admin.ContextServerService
// Method signature:
// <T> T executePostRequest(String siteKey, String path, Object json,
//     List<Cookie> cookies, Map<String, String> headers, Class<T> tClass) throws IOException;

// Check availability first
if (!contextServerService.isAvailable(siteKey)) return;

// Build search condition: find profiles with NotifEnabled = true
Map<String, Object> condition = new HashMap<>();
condition.put("type", "profilePropertyCondition");

Map<String, Object> params = new HashMap<>();
params.put("propertyName",       "properties.MySopraHR_NotifEnabled");
params.put("comparisonOperator", "equals");
params.put("propertyValue",      "true");
condition.put("parameterValues", params);

Map<String, Object> searchRequest = new HashMap<>();
searchRequest.put("condition", condition);
searchRequest.put("offset",    0);
searchRequest.put("limit",     500);

// POST to /cxs/profiles/search — returns Map with "list" key
@SuppressWarnings("unchecked")
Map<String, Object> result = contextServerService.executePostRequest(
    siteKey,
    "/cxs/profiles/search",
    searchRequest,
    null, null,
    Map.class
);

List<Map<String, Object>> profiles =
    (List<Map<String, Object>>) result.getOrDefault("list", List.of());

// Read profile properties
for (Map<String, Object> profile : profiles) {
    Map<String, Object> props = (Map<String, Object>) profile.getOrDefault("properties", Map.of());
    String email     = (String) props.get("email");
    String solution  = (String) props.get("MySopraHR_Solution");
    String frequency = (String) props.getOrDefault("MySopraHR_NotifFrequency", "none");
    Object rawCats   = props.get("MySopraHR_NotifCategories");
    // rawCats may be String or List<String> depending on multivalued type
}
```

### OSGi dependencies (pom.xml)

```xml
<dependency>
    <groupId>org.jahia.modules</groupId>
    <artifactId>jexperience</artifactId>
    <version>3.8.0</version>
    <scope>provided</scope>
</dependency>
<dependency>
    <groupId>org.apache.unomi</groupId>
    <artifactId>unomi-api</artifactId>
    <version>3.0.0</version>
    <scope>provided</scope>
</dependency>
```

### OSGi reference (optional — jExperience may not always be present)

```java
@Reference(cardinality = ReferenceCardinality.OPTIONAL, policy = ReferencePolicy.DYNAMIC)
public void setContextServerService(ContextServerService contextServerService) {
    this.contextServerService = contextServerService;
}
public void unsetContextServerService(ContextServerService contextServerService) {
    this.contextServerService = null;
}
```

---

## Part 6 — Quartz notification job (OSGi)

Pattern from SocialHub — `BackgroundJob` + `SchedulerService`, cluster-aware.

```java
@Component(immediate = true,
    configurationPid = "org.jahia.modules.mymodule.notifications")
public class NotificationDigestJob extends BackgroundJob {

    @interface Config {
        String scheduler_cron() default "0 0 6 * * ?";  // daily 06:00 UTC
        String site_key()       default "mysoprahr";
    }

    private SchedulerService schedulerService;
    private JobDetail jobDetail;
    private String siteKey;

    @Reference
    public void setSchedulerService(SchedulerService schedulerService) {
        this.schedulerService = schedulerService;
    }

    @Activate
    public void activate(Config config) throws Exception {
        this.siteKey = config.site_key();
        jobDetail = BackgroundJob.createJahiaJob("My Digest Job", NotificationDigestJob.class);

        if (schedulerService.getAllJobs(jobDetail.getGroup()).isEmpty()
                && SettingsBean.getInstance().isProcessingServer()) {

            CronTrigger trigger = new CronTrigger(
                "MyDigestTrigger",
                jobDetail.getGroup(),
                jobDetail.getName(),
                jobDetail.getGroup(),
                config.scheduler_cron()
            );
            schedulerService.getScheduler().scheduleJob(jobDetail, trigger);
        }
    }

    @Deactivate
    public void deactivate() throws Exception {
        if (jobDetail != null
                && !schedulerService.getAllJobs(jobDetail.getGroup()).isEmpty()
                && SettingsBean.getInstance().isProcessingServer()) {
            schedulerService.getScheduler().deleteJob(jobDetail.getName(), jobDetail.getGroup());
        }
    }

    @Override
    public void executeJahiaJob(JobExecutionContext ctx) {
        // Quartz creates this class, not OSGi — use BundleUtils for services
        MyDigestService service = BundleUtils.getOsgiService(MyDigestService.class, null);
        if (service == null) return;
        service.runDigest(siteKey);
    }
}
```

---

## Part 7 — Thirdparty IP fix (Docker)

When Jahia and jCustomer run in separate Docker containers, Jahia's IP is NOT `127.0.0.1`. The thirdparty config must include it.

**Find Jahia's Docker IP:**
```bash
docker inspect jcontent-8230 | python3 -c "
import json,sys
d=json.load(sys.stdin)
nets=d[0]['NetworkSettings']['Networks']
for k,v in nets.items(): print(k, v['IPAddress'])
"
```

**Add it to jCustomer's thirdparty config (hot-reload, no restart):**
```bash
docker exec jcustomer_3 sed -i \
  's|ipAddresses:-127.0.0.1,::1}|ipAddresses:-127.0.0.1,::1,172.19.0.2}|' \
  /opt/jcustomer/etc/org.apache.unomi.thirdparty.cfg
```

**Make it permanent** via Docker Compose env var:
```yaml
environment:
  - org.apache.unomi.thirdparty.provider1.ipAddresses=127.0.0.1,::1,172.19.0.2
```

---

## Common errors

| Error | Cause | Fix |
|---|---|---|
| `Event is not allowed : updateProperties` | Event type is thirdparty-restricted | Use `updateUserEfficyPortalData` or another public event type |
| `Event is not allowed : updateProperties` (even with wem) | Jahia's Docker IP not in jCustomer thirdparty allowlist | Add IP to `org.apache.unomi.thirdparty.cfg` |
| Profile props not saved, no error | Property type not defined in jCustomer | Create JSON in `settings/jexperience/properties/` |
| Multivalued prop saved as string | Property defined as `multivalued: false` | Set `multivalued: true` and send JS array in payload |
| `Mapping already exists` warning in logs | Changed `multivalued` on existing prop | Elasticsearch mapping is immutable; delete and recreate the property type if needed |
| `window.wem` is undefined | jExperience not configured for the site or not loaded | Check jExperience site configuration; guard with `if (!window.wem) return` |
| Categories fetch returns empty | GraphQL query path wrong or workspace mismatch | Use `workspace: LIVE` for published categories |

---

## Quick reference

| Operation | Method |
|---|---|
| Read profile (browser) | `POST /modules/jexperience/proxy/{siteKey}/context.json` with `requiredProfileProperties` |
| Update profile (browser) | `window.wem.collectEvent` with `updateUserEfficyPortalData` event |
| Query profiles (server) | `ContextServerService.executePostRequest(siteKey, "/cxs/profiles/search", query, ...)` |
| Deploy property type | JSON in `settings/jexperience/properties/` |
| Deploy rule | JSON in `settings/jexperience/rules/` |
| Check if rule exists | `curl -u karaf:karaf http://localhost:8181/cxs/rules/{ruleId}` |
| Check thirdparty config | `docker exec jcustomer_3 cat /opt/jcustomer/etc/org.apache.unomi.thirdparty.cfg` |
