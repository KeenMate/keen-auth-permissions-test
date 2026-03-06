defmodule KeenAuthPermissionsTest.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @source "test_app"
  @tenant_id 1

  @impl true
  def start(_type, _args) do
    children = [
      KeenAuthPermissionsTestWeb.Telemetry,
      # Database
      KeenAuthPermissionsTest.Repo,
      {DNSCluster,
       query: Application.get_env(:keen_auth_permissions_test, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: KeenAuthPermissionsTest.PubSub},
      # SSE presence tracking
      KeenAuth.SSE.Supervisor,
      # Permissions full_code ↔ short_code cache
      KeenAuthPermissions.PermissionsMap,
      # PostgreSQL LISTEN/NOTIFY → SSE bridge
      KeenAuthPermissions.PgListener,
      # Start to serve requests, typically the last entry
      KeenAuthPermissionsTestWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: KeenAuthPermissionsTest.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Ensure required seed data exists after the app is started.
    # Order matters: providers → resource types → permissions → groups → perm sets → mappings
    ensure_providers()
    ensure_token_types()
    ensure_resource_types()
    ensure_permissions()
    ensure_user_groups()
    ensure_perm_sets()
    ensure_group_mappings()

    result
  end

  defp ensure_providers do
    db_context = KeenAuthPermissions.DbContext.get_global_db_context()

    # {code, name, allows_group_mapping, allows_group_sync}
    providers = [
      {"email", "Email", false, false},
      {"entra", "Microsoft Entra ID", true, true}
    ]

    for {code, name, mapping, sync} <- providers do
      case db_context.auth_ensure_provider(
             "system",
             1,
             "app-startup",
             code,
             name,
             true,
             mapping,
             sync
           ) do
        {:ok, [%{is_new: true}]} ->
          Logger.info("Created provider: #{code}")

        {:ok, [%{is_new: false}]} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to ensure provider '#{code}': #{inspect(reason)}")
      end
    end
  end

  defp ensure_token_types do
    alias KeenAuthPermissions.TokenTypes
    alias KeenAuthPermissions.RequestContext

    ctx = RequestContext.system_ctx()

    # 86400 seconds = 24 hours default expiration, tenant_id 1
    case TokenTypes.ensure_exists(ctx, "email_confirmation", 86400, @tenant_id) do
      {:ok, :exists} ->
        :ok

      {:ok, _created} ->
        Logger.info("Created token type: email_confirmation")

      {:error, reason} ->
        Logger.warning("Failed to ensure token type 'email_confirmation': #{inspect(reason)}")
    end
  end

  defp ensure_resource_types do
    alias KeenAuthPermissions.ResourceAccess
    alias KeenAuthPermissions.RequestContext

    ctx = RequestContext.system_ctx()

    resource_types = [
      %{
        code: "project",
        title: "Project",
        parent_code: nil,
        description: "Top-level project resource"
      },
      %{
        code: "project.documents",
        title: "Documents",
        parent_code: "project",
        description: "Project documents"
      },
      %{
        code: "project.invoices",
        title: "Invoices",
        parent_code: "project",
        description: "Project invoices"
      }
    ]

    case ResourceAccess.ensure_resource_types(ctx, resource_types, @source, @tenant_id) do
      {:ok, results} ->
        for r <- results, do: Logger.info("Ensured resource type: #{r.code}")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to ensure resource types: #{inspect(reason)}")
    end
  end

  defp ensure_permissions do
    alias KeenAuthPermissions.Permissions
    alias KeenAuthPermissions.RequestContext

    ctx = RequestContext.system_ctx()

    permissions = [
      # admin hierarchy
      %{title: "Admin", parent_code: nil, is_assignable: false, short_code: nil},
      %{title: "Read", parent_code: "admin", is_assignable: true, short_code: "admin.read"},
      %{title: "Write", parent_code: "admin", is_assignable: true, short_code: "admin.write"},
      %{title: "Delete", parent_code: "admin", is_assignable: true, short_code: "admin.delete"},
      # users hierarchy
      %{title: "Users", parent_code: nil, is_assignable: false, short_code: nil},
      %{title: "Read", parent_code: "users", is_assignable: true, short_code: "users.read"},
      %{title: "Write", parent_code: "users", is_assignable: true, short_code: "users.write"},
      %{title: "Delete", parent_code: "users", is_assignable: true, short_code: "users.delete"},
      # groups hierarchy
      %{title: "Groups", parent_code: nil, is_assignable: false, short_code: nil},
      %{title: "Read", parent_code: "groups", is_assignable: true, short_code: "groups.read"},
      %{title: "Write", parent_code: "groups", is_assignable: true, short_code: "groups.write"},
      # super hierarchy
      %{title: "Super", parent_code: nil, is_assignable: false, short_code: nil},
      %{title: "Admin", parent_code: "super", is_assignable: true, short_code: "super.admin"}
    ]

    # is_final_state: true means "delete permissions from this source that are not in the list"
    case Permissions.ensure(ctx, permissions, @source, true) do
      {:ok, _results} ->
        Logger.info("Permissions ensured (source: #{@source})")

      {:error, reason} ->
        Logger.warning("Failed to ensure permissions: #{inspect(reason)}")
    end
  end

  defp ensure_user_groups do
    alias KeenAuthPermissions.UserGroups
    alias KeenAuthPermissions.RequestContext

    ctx = RequestContext.system_ctx()

    user_groups = [
      %{
        title: "Full Admins",
        is_assignable: true,
        is_active: true,
        is_external: false,
        is_default: false
      },
      %{
        title: "Moderators",
        is_assignable: true,
        is_active: true,
        is_external: false,
        is_default: false
      },
      %{
        title: "Viewers",
        is_assignable: true,
        is_active: true,
        is_external: false,
        is_default: true
      }
    ]

    # is_final_state: true syncs groups from this source
    case UserGroups.ensure(ctx, user_groups, @tenant_id, @source, true) do
      {:ok, _results} ->
        Logger.info("User groups ensured (source: #{@source})")

      {:error, reason} ->
        Logger.warning("Failed to ensure user groups: #{inspect(reason)}")
    end
  end

  defp ensure_perm_sets do
    alias KeenAuthPermissions.PermSets
    alias KeenAuthPermissions.RequestContext

    ctx = RequestContext.system_ctx()

    perm_sets = [
      %{
        title: "Admin",
        is_system: false,
        is_assignable: true,
        permissions: [
          "admin.read",
          "admin.write",
          "admin.delete",
          "users.read",
          "users.write",
          "users.delete",
          "groups.read",
          "groups.write",
          "super.admin"
        ]
      },
      %{
        title: "Moderator",
        is_system: false,
        is_assignable: true,
        permissions: ["admin.read", "users.read", "users.write", "groups.read"]
      },
      %{
        title: "Viewer",
        is_system: false,
        is_assignable: true,
        permissions: ["admin.read", "users.read", "groups.read"]
      }
    ]

    # is_final_state: true syncs perm sets from this source
    case PermSets.ensure(ctx, perm_sets, @source, @tenant_id, true) do
      {:ok, _results} ->
        Logger.info("Permission sets ensured (source: #{@source})")

      {:error, reason} ->
        Logger.warning("Failed to ensure perm sets: #{inspect(reason)}")
    end
  end

  defp ensure_group_mappings do
    alias KeenAuthPermissions.UserGroups
    alias KeenAuthPermissions.RequestContext

    ctx = RequestContext.system_ctx()

    # Map Entra AD roles → internal user groups (by title)
    mappings = [
      %{
        user_group_title: "Full Admins",
        provider_code: "entra",
        mapped_object_id: nil,
        mapped_object_name: nil,
        mapped_role: "Admins.FullAdmin"
      }
    ]

    case UserGroups.ensure_mappings(ctx, mappings, @tenant_id, true) do
      {:ok, _results} ->
        Logger.info("Group mappings ensured")

      {:error, reason} ->
        Logger.warning("Failed to ensure group mappings: #{inspect(reason)}")
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
