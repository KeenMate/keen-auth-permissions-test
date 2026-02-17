defmodule KeenAuthPermissionsTest.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      KeenAuthPermissionsTestWeb.Telemetry,
      # Database
      KeenAuthPermissionsTest.Repo,
      {DNSCluster, query: Application.get_env(:keen_auth_permissions_test, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: KeenAuthPermissionsTest.PubSub},
      # Start to serve requests, typically the last entry
      KeenAuthPermissionsTestWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: KeenAuthPermissionsTest.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Ensure required token types exist after the app is started
    ensure_token_types()

    result
  end

  defp ensure_token_types do
    alias KeenAuthPermissions.TokenTypes
    alias KeenAuthPermissions.RequestContext

    ctx = RequestContext.system_ctx()

    # 86400 seconds = 24 hours default expiration, tenant_id 1
    case TokenTypes.ensure_exists(ctx, "email_confirmation", 86400, 1) do
      {:ok, :exists} ->
        :ok

      {:ok, _created} ->
        require Logger
        Logger.info("Created token type: email_confirmation")

      {:error, reason} ->
        require Logger
        Logger.warning("Failed to ensure token type 'email_confirmation': #{inspect(reason)}")
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KeenAuthPermissionsTestWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
