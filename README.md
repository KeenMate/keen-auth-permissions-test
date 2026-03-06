# KeenAuth Permissions Test App

A comprehensive Phoenix LiveView application showcasing the full capabilities of `keen_auth`, `keen_auth_permissions`, and `keen_microsoft_graphapi` libraries. Serves as both a reference implementation and an interactive admin panel for managing users, groups, permissions, tenants, and more.

## What This Project Showcases

### keen_auth_permissions — Full CRUD Admin UI
- **Users** — search, view detail, edit user data, enable/disable, lock/unlock, view events & journal
- **User Groups** — search, create, delete, view members (add/remove), manage provider mappings, assign permissions & permission sets
- **Permissions** — browse all permissions with search
- **Permission Sets** — create, edit, manage assigned permissions, inline editing
- **Tenants** — create (with auto-generated code), edit, delete, view members & groups
- **Resource Types** — create (with auto-generated code), browse hierarchy
- **Resource Access** — grant/deny/revoke access, check access flags, view access matrix, browse user resources
- **Blacklist** — add/remove entries, search with pagination
- **MFA** — enroll TOTP, confirm challenges, manage policies, reset/disable, verify users by email
- **Events** — filterable event log with detail modals
- **Ensure functions** — bulk-ensure permissions, permission sets, user groups, user group mappings, and resource types on app startup

### keen_microsoft_graphapi — Azure AD Integration
- **AAD Group Browser** — search and browse Azure AD groups via Microsoft Graph API, select to auto-fill provider mapping forms
- **AAD User Search** — search Azure AD users and add them as local group members (auto-creates local user via `ensure_user_info` if they haven't signed in yet)

### keen_auth — Authentication
- **Azure AD (Microsoft Entra ID)** OAuth authentication with automatic user provisioning
- **Email/password** authentication with registration and Pbkdf2 hashing

### General Patterns
- **Sidebar navigation** with shared `admin_layout` component
- **SSE-based auth event handling** — real-time permission/session updates via PubSub
- **RequestContext** — JSONB-based request context passed to all database operations
- **Reusable UI components** — `action_icon`, `admin_layout`, `pagination`, `auth_event_listener`
- **DaisyUI + Tailwind CSS** — consistent table layouts with Actions-first columns and icon buttons

## Setup

### Quick Start

```bash
# Install dependencies
mix deps.get

# Configure local settings
cp config/.local.exs.example config/.local.exs
# Edit config/.local.exs with your credentials

# Start the server
mix phx.server
# Or with Makefile
make dev
```

Visit [`localhost:4000`](http://localhost:4000)

### Database Setup

This app requires the [postgresql-permissions-model](https://github.com/KeenMate/postgresql-permissions-model) database.

```bash
# Run database setup (if using Makefile)
make setup
```

Or configure database connection in `config/dev.exs` or `config/.local.exs`:

```elixir
config :keen_auth_permissions_test, KeenAuthPermissionsTest.Repo,
  username: "your_username",
  password: "your_password",
  hostname: "localhost",
  database: "postgresql_permissionmodel",
  port: 5432
```

### Azure AD Configuration

1. Register an app in Azure Portal > App Registrations
2. Set the redirect URI to `http://localhost:4000/auth/entra/callback`
3. Create a client secret
4. Add to `config/.local.exs`:

```elixir
# OAuth login
config :keen_auth_permissions_test, :keen_auth,
  strategies: [
    entra: [
      config: [
        client_id: "your-client-id",
        client_secret: "your-client-secret",
        tenant_id: "your-tenant-id"
      ]
    ]
  ]

# Graph API (for AAD group/user browsing)
config :keen_microsoft_graphapi, :config,
  tenant_id: "your-tenant-id",
  client_id: "your-client-id",
  client_secret: "your-client-secret"
```

## Pages

| Route | Description | Auth Required |
|-------|-------------|---------------|
| `/` | Home page | No |
| `/login` | Login with email or OAuth | No |
| `/register` | Email registration form | No |
| `/dashboard` | Admin dashboard with navigation cards | Yes |
| `/users` | Users list with search | Yes |
| `/users/:id` | User detail — profile, groups, permissions, events, journal | Yes |
| `/groups` | Groups list with search and delete | Yes |
| `/groups/:id` | Group detail — members, mappings, permissions, perm sets | Yes |
| `/permissions` | Permissions list with search | Yes |
| `/perm-sets` | Permission sets with inline editing | Yes |
| `/perm-sets/:id` | Permission set detail — info, assigned permissions | Yes |
| `/tenants` | Tenants list with inline editing | Yes |
| `/tenants/:id` | Tenant detail — info, members, groups | Yes |
| `/resource-types` | Resource types list with create modal | Yes |
| `/resource-access` | Resource access — grants, access check, flags, matrix | Yes |
| `/events` | User events viewer with filters | Yes |
| `/blacklist` | Blacklist management with search | Yes |
| `/mfa` | MFA enrollment, policies, verify, login failure tracking | Yes |
| `/demo` | Permission helpers demo | Yes |

## Permission Helpers Demo

The `/demo` page demonstrates the `KeenAuthPermissions.PermissionHelpers` module:

```elixir
# Boolean checks
PermissionHelpers.has_any?(user, ["admin.read", "super.admin"])
PermissionHelpers.has_all?(user, ["users.read", "users.write"])
PermissionHelpers.in_any_group?(user, ["admins", "moderators"])

# Result-based checks (for with blocks)
with {:ok, :authorized} <- PermissionHelpers.require_any(user, ["admin.read"]),
     {:ok, data} <- fetch_data() do
  {:ok, data}
end

# Function wrappers
PermissionHelpers.with_permission(user, ["admin.delete"], fn ->
  delete_record(id)
end)
```

## Project Structure

```
lib/
├── keen_auth_permissions_test/
│   ├── auth/
│   │   ├── email_handler.ex      # Email authentication handler
│   │   └── processor.ex          # Auth processor for all providers
│   ├── application.ex            # App startup with ensure_* bulk operations
│   ├── database.ex               # Database context module
│   └── repo.ex                   # Ecto repository
└── keen_auth_permissions_test_web/
    ├── components/
    │   ├── core_components.ex    # admin_layout, action_icon, pagination
    │   └── auth_components.ex    # auth_event_listener
    ├── controllers/
    │   └── page_controller.ex    # Login, register, dashboard
    └── live/
        ├── helpers/
        │   └── aad_browser.ex    # Microsoft Graph API search helper
        ├── users_live.ex         # Users management
        ├── user_detail_live.ex   # User detail (profile, groups, perms, events, journal)
        ├── groups_live.ex        # Groups management
        ├── group_detail_live.ex  # Group detail (members, mappings, perms, perm sets, AAD)
        ├── permissions_live.ex   # Permissions listing
        ├── perm_sets_live.ex     # Permission sets management
        ├── perm_set_detail_live.ex # Perm set detail (info, permissions)
        ├── tenants_live.ex       # Tenants management
        ├── tenant_detail_live.ex # Tenant detail (info, members, groups)
        ├── resource_types_live.ex # Resource types
        ├── resource_access_live.ex # Resource access (grants, check, flags, matrix)
        ├── events_live.ex        # Events viewer
        ├── blacklist_live.ex     # Blacklist management
        ├── mfa_live.ex           # MFA management
        └── demo_live.ex          # Permission helpers demo
```

## Dependencies

- `keen_auth` ~> 1.0 — OAuth and email authentication
- `keen_auth_permissions` — permissions, users, groups, tenants, resource access (local path)
- `keen_microsoft_graphapi` — Azure AD group/user browsing via Microsoft Graph API (local path)
- `pbkdf2_elixir` — password hashing
- Phoenix 1.8, Phoenix LiveView 1.1
- DaisyUI 5 (via Tailwind)
