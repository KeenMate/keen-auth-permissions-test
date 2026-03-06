# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :keen_auth_permissions_test,
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :keen_auth_permissions_test, KeenAuthPermissionsTestWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [
      html: KeenAuthPermissionsTestWeb.ErrorHTML,
      json: KeenAuthPermissionsTestWeb.ErrorJSON
    ],
    layout: false
  ],
  pubsub_server: KeenAuthPermissionsTest.PubSub,
  live_view: [signing_salt: "NjADI735"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  keen_auth_permissions_test: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  keen_auth_permissions_test: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# KeenAuth configuration
config :keen_auth,
  email_enabled: true,
  storage_options: [store_tokens: false],
  sse: [
    pubsub: KeenAuthPermissionsTest.PubSub,
    heartbeat_interval: 30_000
  ]

# KeenAuthPermissions configuration
config :keen_auth_permissions,
  db_context: KeenAuthPermissionsTest.Database,
  tenant: 1,
  context_extra_fields: [:session_id],
  notifier: [
    enabled: true,
    pubsub: KeenAuthPermissionsTest.PubSub
  ],
  pg_listener: [
    enabled: true,
    repo: KeenAuthPermissionsTest.Repo,
    pubsub: KeenAuthPermissionsTest.PubSub,
    channels: ["auth_events"],
    debounce_interval: 200
  ]

# KeenAuth strategies - Azure AD (Entra ID) and Email
config :keen_auth_permissions_test, :keen_auth,
  tenant: 1,
  strategies: [
    entra: [
      label: "Microsoft Entra",
      icon: "microsoft",
      color: "#0078d4",
      strategy: Assent.Strategy.AzureAD,
      mapper: KeenAuth.Mapper.AzureAD,
      processor: KeenAuthPermissions.Processor.AzureAD,
      config: [
        client_id: "CONFIGURE_IN_LOCAL_EXS",
        client_secret: "CONFIGURE_IN_LOCAL_EXS",
        tenant_id: "CONFIGURE_IN_LOCAL_EXS",
        redirect_uri: "http://localhost:4000/auth/entra/callback"
      ]
    ],
    email: [
      label: "Email",
      icon: "email",
      color: "#4ade80",
      authentication_handler: KeenAuthPermissionsTest.Auth.EmailHandler,
      mapper: KeenAuth.Mapper.Default,
      processor: KeenAuthPermissionsTest.Auth.Processor
    ]
  ]

# Use Req HTTP adapter for Assent
config :assent, http_adapter: Assent.HTTPAdapter.Req

# Microsoft Graph API configuration
config :keen_microsoft_graphapi, :config,
  tenant_id: "CONFIGURE_IN_LOCAL_EXS",
  client_id: "CONFIGURE_IN_LOCAL_EXS",
  client_secret: "CONFIGURE_IN_LOCAL_EXS"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# Import local config (gitignored) for secrets
File.regular?("config/.local.exs") && import_config(".local.exs")
