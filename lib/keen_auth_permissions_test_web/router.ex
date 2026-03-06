defmodule KeenAuthPermissionsTestWeb.Router do
  use KeenAuthPermissionsTestWeb, :router

  require KeenAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug KeenAuthPermissionsTestWeb.Plugs.SessionId
    plug :fetch_live_flash
    plug :put_root_layout, html: {KeenAuthPermissionsTestWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # Browser without CSRF - for OAuth callbacks from external providers
  pipeline :browser_no_csrf do
    plug :accepts, ["html"]
    plug :fetch_session
    plug KeenAuthPermissionsTestWeb.Plugs.SessionId
    plug :fetch_live_flash
    plug :put_root_layout, html: {KeenAuthPermissionsTestWeb.Layouts, :root}
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # KeenAuth pipeline - stores config in connection + auth session cookie
  pipeline :authentication do
    plug KeenAuth.Plug, otp_app: :keen_auth_permissions_test
    plug KeenAuth.Plug.AuthSession, secure: false, same_site: "Lax"
  end

  # Optional auth - fetch user if logged in, but don't require it
  pipeline :maybe_auth do
    plug KeenAuth.Plug.FetchUser

    plug KeenAuthPermissions.Plug.RevalidateSession,
      on_invalid: &KeenAuthPermissions.Plug.RevalidateSession.clear_user/2
  end

  # Require authentication
  pipeline :require_auth do
    plug KeenAuth.Plug.FetchUser
    plug KeenAuthPermissions.Plug.RevalidateSession
    plug KeenAuth.Plug.RequireAuthenticated, redirect: "/login"
  end

  # Public routes with optional user display
  scope "/", KeenAuthPermissionsTestWeb do
    pipe_through [:browser, :authentication, :maybe_auth]

    get "/", PageController, :home
    live "/demo", DemoLive
  end

  # Login and registration pages
  scope "/", KeenAuthPermissionsTestWeb do
    pipe_through [:browser, :authentication]

    get "/login", PageController, :login
    get "/register", PageController, :register
    post "/register", PageController, :create_registration
    get "/confirm", PageController, :confirm
    live "/mfa/setup", MfaSetupLive
  end

  # Email authentication routes (need CSRF protection)
  scope "/auth/email" do
    pipe_through [:browser, :authentication]

    post "/new", KeenAuth.EmailAuthenticationController, :new
  end

  # OAuth routes (no CSRF - callbacks come from external providers)
  scope "/auth" do
    pipe_through [:browser_no_csrf, :authentication]

    scope "/:provider" do
      get "/new", KeenAuth.AuthenticationController, :new
      get "/callback", KeenAuth.AuthenticationController, :callback
      post "/callback", KeenAuth.AuthenticationController, :callback
      get "/delete", KeenAuth.AuthenticationController, :delete
    end

    get "/delete", KeenAuth.AuthenticationController, :delete
  end

  # Session clear endpoint (JS-friendly, no redirect)
  scope "/auth" do
    pipe_through [:browser, :authentication]

    post "/clear", KeenAuth.SessionClearPlug, []
  end

  # SSE endpoint for real-time notifications
  scope "/auth" do
    pipe_through [:browser, :authentication, :require_auth]

    get "/events/stream", KeenAuth.SSE.Plug, []
  end

  # Protected routes (require authentication)
  scope "/", KeenAuthPermissionsTestWeb do
    pipe_through [:browser, :authentication, :require_auth]

    get "/dashboard", PageController, :dashboard
    live "/users", UsersLive
    live "/users/:user_id", UserDetailLive
    live "/groups", GroupsLive
    live "/groups/:group_id", GroupDetailLive
    live "/permissions", PermissionsLive
    live "/events", EventsLive
    live "/perm-sets", PermSetsLive
    live "/perm-sets/:perm_set_id", PermSetDetailLive
    live "/tenants", TenantsLive
    live "/tenants/:tenant_id", TenantDetailLive
    live "/resource-types", ResourceTypesLive
    live "/resource-access", ResourceAccessLive
    live "/blacklist", BlacklistLive
    live "/mfa", MfaLive
  end
end
