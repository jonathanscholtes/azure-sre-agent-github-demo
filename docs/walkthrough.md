# Walkthrough

Instructions for injecting a failure, generating errors, and observing the self-healing pipeline end to end.

---

## Step 1 — Inject the bug and generate errors

```powershell
.\tools\Start-SreDemo.ps1
```

This patches a realistic bug into the order management API, rebuilds and redeploys the container image via ACR, waits for the new revision to become healthy, then fires a burst of 20 orders to flood Application Insights with errors. Direct portal deep-links are printed for every presenter step.

```powershell
# Inject a specific bug type with a larger load burst
.\tools\Start-SreDemo.ps1 -Bug KeyError -LoadCount 30

# Patch source only — let GitHub Actions CI/CD handle the deploy
.\tools\Start-SreDemo.ps1 -SkipDeploy
```

**Bug types:**

| Bug | What breaks | Symptom |
|-----|-------------|---------|
| `KeyError` | `unit_price` key renamed to `price` in invoice calculation | Every `POST /api/orders/{id}/process` returns 500 |
| `AttributeError` | `req.lineItems` accessed instead of `req.line_items` | Every `POST /api/orders` returns 500 |
| `Random` | One of the above, chosen at random (default) | |

> **`-SkipDeploy`** patches the source file and writes `.chaos-state` but skips the ACR build. Commit and push to trigger the GitHub Actions workflow — useful for demonstrating the full CI/CD path.

---

## Step 2 — Walkthrough

| Step | Where to look | What to show |
|------|---------------|-------------|
| 1 | Application Insights → **Failures** blade | Error rate spike, exception type, stack trace |
| 2 | [Azure SRE Agent](https://learn.microsoft.com/en-us/azure/sre-agent/overview?tabs=task) portal | Agent investigating the anomaly in real time |
| 3 | Azure DevOps Boards | ADO WorkItem auto-created with telemetry deep-link |
| 4 | GitHub Issues | Issue created by SRE Agent, assigned to GitHub Copilot |
| 5 | GitHub Pull Requests | Copilot's fix PR on a new branch |
| 6 | Merge the PR | CI/CD pipeline triggers; error rate returns to zero |

---

## Step 3 — Reset after the demo

```powershell
.\tools\Invoke-ChaosBug.ps1 -Revert `
    -ContainerRegistryName <acr-name> `
    -ResourceGroupName     <resource-group> `
    -BackendAppName        <container-app-name>
```

`Start-SreDemo.ps1` prints the exact reset command with your environment's resource names at the end of its output.

---

## API Reference

The FastAPI backend exposes interactive docs at `<api-url>/docs`.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check including Cosmos DB connectivity |
| GET | `/api/customers` | List customers |
| GET | `/api/orders` | List orders |
| POST | `/api/orders` | Create an order |
| GET | `/api/orders/{id}` | Get order details |
| POST | `/api/orders/{id}/process` | Process an order — invoice generation (bug injection target) |
| POST | `/api/demo/seed` | Seed sample customers and orders |
| POST | `/api/demo/simulate-load` | Generate a synthetic load burst |
