# KeenAuth Permissions Test App

A demonstration Phoenix LiveView application showing integration of `keen_auth` and `keen_auth_permissions`.

## Features

- **Multiple Authentication Methods**
  - Azure AD (Microsoft Entra ID) OAuth authentication
  - Email/password authentication with registration
- **Admin Pages** (LiveView)
  - Users management with search
  - Groups management with search
  - Permissions listing with search
  - User Events viewer with filters
- **Permission Helpers Demo**
  - Interactive demo of in-memory permission checking
  - Shows `PermissionHelpers` usage patterns
- **Modern UI**
  - DaisyUI components with Tailwind CSS
  - Responsive design

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
```

## Pages

| Route | Description | Auth Required |
|-------|-------------|---------------|
| `/` | Home page | No |
| `/login` | Login with email or OAuth | No |
| `/register` | Email registration form | No |
| `/demo` | Permission helpers demo | No |
| `/dashboard` | User dashboard | Yes |
| `/users` | Users list with search | Yes |
| `/groups` | Groups list with search | Yes |
| `/permissions` | Permissions list with search | Yes |
| `/events` | User events viewer | Yes |

## Email Authentication

The app supports email/password authentication:

1. Visit `/register` to create an account
2. Visit `/login` to sign in with email and password

Passwords are hashed using Pbkdf2 (secure, pure Elixir implementation).

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

## User Events

The `/events` page shows user authentication events:

- Login successes and failures
- User registrations
- Filterable by event type, user, and date range
- Shows IP address, user agent, and event details

## Project Structure

```
lib/
├── keen_auth_permissions_test/
│   ├── auth/
│   │   ├── email_handler.ex    # Email authentication handler
│   │   └── processor.ex        # Auth processor for all providers
│   ├── database.ex             # Database context module
│   └── repo.ex                 # Ecto repository
└── keen_auth_permissions_test_web/
    ├── controllers/
    │   └── page_controller.ex  # Login, register, dashboard
    └── live/
        ├── users_live.ex       # Users management
        ├── groups_live.ex      # Groups management
        ├── permissions_live.ex # Permissions listing
        ├── events_live.ex      # Events viewer
        └── demo_live.ex        # Permission helpers demo
```

## Dependencies

- `keen_auth` ~> 1.0 - OAuth authentication
- `keen_auth_permissions` - Permissions management (local path)
- `pbkdf2_elixir` - Password hashing
- Phoenix 1.8, Phoenix LiveView 1.1
- DaisyUI 5 (via Tailwind)
