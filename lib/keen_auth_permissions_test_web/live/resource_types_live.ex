defmodule KeenAuthPermissionsTestWeb.ResourceTypesLive do
  use KeenAuthPermissionsTestWeb, :live_view
  require Logger
  alias KeenAuthPermissions.ResourceAccess
  alias KeenAuthPermissions.RequestContext
  alias KeenAuthPermissions.User
  alias KeenAuthPermissionsTestWeb.AuthEventHandler
  @impl true
  def mount(_params, session, socket) do
    user = session["current_user"]
    if is_nil(user) do
      {:ok, push_navigate(socket, to: "/login")}
    else
      if connected?(socket) do
        Phoenix.PubSub.subscribe(
          KeenAuthPermissionsTest.PubSub,
          "keen_auth:user:#{user.user_id}"
        )
      end
      ctx = build_context(user)
      {:ok,
       socket
       |> assign(
         page_title: "Resource Types",
         user: user,
         ctx: ctx,
         resource_types: [],
         loading: true,
         error: nil,
         auth_blocked: false,
         auth_warning: false,
         auth_warning_message: "",
         # Create modal
         show_create_modal: false,
         create_form: %{
           "code" => "",
           "title" => "",
           "parent_code" => "",
           "description" => "",
           "source" => ""
         },
         create_saving: false,
         create_error: nil,
         code_touched: false
       )
       |> load_resource_types()}
    end
  end
  @impl true
  def handle_info({:sse_event, event, payload}, socket) do
    {:noreply, AuthEventHandler.handle_sse_event(socket, event, payload, &load_resource_types/1)}
  end
  @impl true
  def handle_event("dismiss_auth_warning", _params, socket) do
    {:noreply, assign(socket, auth_warning: false, auth_warning_message: "")}
  end
  # ============================================================================
  # Create
  # ============================================================================
  def handle_event("open_create_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_create_modal: true,
       create_form: %{
         "code" => "",
         "title" => "",
         "parent_code" => "",
         "description" => "",
         "source" => ""
       },
       create_error: nil,
       code_touched: false
     )}
  end
  def handle_event("close_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: false, create_error: nil)}
  end
  def handle_event("create_form_change", params, socket) do
    code_touched = socket.assigns.code_touched
    # If user manually edits the code field, mark it as touched
    code_touched =
      if params["code"] != socket.assigns.create_form["code"] do
        true
      else
        code_touched
      end
    # Auto-generate code from title unless user has manually edited code
    params =
      if not code_touched do
        Map.put(params, "code", title_to_code(params["title"] || ""))
      else
        params
      end
    {:noreply, assign(socket, create_form: params, code_touched: code_touched)}
  end
  def handle_event("create_resource_type", params, socket) do
    %{ctx: ctx} = socket.assigns
    code = String.trim(params["code"] || "")
    title = String.trim(params["title"] || "")
    parent_code = blank_to_nil(params["parent_code"])
    description = blank_to_nil(params["description"])
    source = blank_to_nil(params["source"])
    cond do
      title == "" ->
        {:noreply, assign(socket, create_error: "Title is required")}
      code == "" ->
        {:noreply, assign(socket, create_error: "Code is required")}
      true ->
        socket = assign(socket, create_saving: true, create_error: nil)
        case ResourceAccess.create_resource_type(ctx, code, title, parent_code, description, 1, source) do
          {:ok, _result} ->
            {:noreply,
             socket
             |> assign(show_create_modal: false, create_saving: false)
             |> put_flash(:info, "Resource type \"#{title}\" created")
             |> load_resource_types()}
          {:error, reason} ->
            Logger.error("Failed to create resource type", reason: inspect(reason))
            {:noreply,
             assign(socket,
               create_saving: false,
               create_error: "Failed to create: #{inspect(reason)}"
             )}
        end
    end
  end
  # ============================================================================
  # Private
  # ============================================================================
  defp load_resource_types(socket) do
    case ResourceAccess.list_resource_types() do
      {:ok, resource_types} ->
        assign(socket, resource_types: resource_types, loading: false, error: nil)
      {:error, reason} ->
        Logger.error("Failed to load resource types", reason: inspect(reason))
        assign(socket,
          resource_types: [],
          loading: false,
          error: "Failed to load resource types: #{inspect(reason)}"
        )
    end
  end
  defp title_to_code(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, "")
    |> String.trim()
    |> String.replace(~r/\s+/, "_")
  end
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(str) when is_binary(str) do
    case String.trim(str) do
      "" -> nil
      trimmed -> trimmed
    end
  end
  defp build_context(%User{} = user) do
    RequestContext.new(user)
  end
  # ============================================================================
  # Render
  # ============================================================================
  @impl true
  def render(assigns) do
    ~H"""
    <.auth_event_listener auth_blocked={@auth_blocked} auth_warning={@auth_warning} auth_warning_message={@auth_warning_message} />
    <.admin_layout current_page={:resource_types}>
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">Resource Types</h1>
          <div class="breadcrumbs text-sm">
            <ul>
              <li><a href="/">Home</a></li>
              <li><a href="/dashboard">Dashboard</a></li>
              <li>Resource Types</li>
            </ul>
          </div>
        </div>
        <%= if @error do %>
          <div class="alert alert-error mb-4">
            <span><%= @error %></span>
          </div>
        <% end %>
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <div class="flex items-center gap-4 mb-4">
              <div class="flex-1">
                <h2 class="card-title">Resource Types</h2>
              </div>
              <button phx-click="open_create_modal" class="btn btn-primary">
                New Resource Type
              </button>
            </div>
          </div>
        </div>
        <div class="card bg-base-100 shadow-xl mt-4">
          <div class="card-body">
            <%= if @loading do %>
              <div class="flex justify-center py-8">
                <span class="loading loading-spinner loading-lg"></span>
              </div>
            <% else %>
              <div class="overflow-x-auto">
                <table class="table table-zebra">
                  <thead>
                    <tr>
                      <th>Code</th>
                      <th>Title</th>
                      <th>Full Title</th>
                      <th>Description</th>
                      <th>Parent Code</th>
                      <th>Path</th>
                      <th>Active</th>
                      <th>Source</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for rt <- @resource_types do %>
                      <tr>
                        <td><code class="text-sm"><%= rt.code %></code></td>
                        <td><%= rt.title %></td>
                        <td><%= rt.full_title || "-" %></td>
                        <td><%= rt.description || "-" %></td>
                        <td>
                          <%= if rt.parent_code do %>
                            <code class="text-sm"><%= rt.parent_code %></code>
                          <% else %>
                            <span class="text-base-content/30">-</span>
                          <% end %>
                        </td>
                        <td>
                          <%= if rt.path do %>
                            <code class="text-xs"><%= rt.path %></code>
                          <% else %>
                            <span class="text-base-content/30">-</span>
                          <% end %>
                        </td>
                        <td>
                          <%= if rt.is_active do %>
                            <span class="badge badge-success badge-sm">Yes</span>
                          <% else %>
                            <span class="badge badge-ghost badge-sm">No</span>
                          <% end %>
                        </td>
                        <td><%= rt.source || "-" %></td>
                      </tr>
                    <% end %>
                    <%= if Enum.empty?(@resource_types) do %>
                      <tr>
                        <td colspan="8" class="text-center text-base-content/50 py-8">
                          No resource types found
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>

    <%!-- Create Resource Type Modal --%>
    <%= if @show_create_modal do %>
      <div class="modal modal-open">
        <div class="modal-box w-full max-w-2xl">
          <h3 class="font-bold text-lg mb-6">Create New Resource Type</h3>
          <%= if @create_error do %>
            <div class="alert alert-error mb-4">
              <span><%= @create_error %></span>
            </div>
          <% end %>
          <form phx-submit="create_resource_type" phx-change="create_form_change">
            <table class="table">
              <tbody>
                <tr>
                  <th class="w-48 align-middle">Parent Code</th>
                  <td>
                    <select name="parent_code" class="select select-bordered w-full">
                      <option value="" selected={@create_form["parent_code"] == ""}>
                        None (root type)
                      </option>
                      <%= for rt <- @resource_types do %>
                        <option value={rt.code} selected={@create_form["parent_code"] == rt.code}>
                          <%= rt.full_title %> (<%= rt.code %>)
                        </option>
                      <% end %>
                    </select>
                  </td>
                </tr>
                <tr>
                  <th class="align-middle">Title</th>
                  <td>
                    <input
                      type="text"
                      name="title"
                      value={@create_form["title"]}
                      placeholder="e.g. Project Documents"
                      class="input input-bordered w-full"
                      required
                    />
                  </td>
                </tr>
                <tr>
                  <th class="align-middle">Code</th>
                  <td>
                    <input
                      type="text"
                      name="code"
                      value={@create_form["code"]}
                      placeholder="Auto-generated from title"
                      class="input input-bordered w-full"
                      required
                    />
                    <label class="label">
                      <span class="label-text-alt">Auto-generated from title. Edit to override.</span>
                    </label>
                  </td>
                </tr>
                <tr>
                  <th class="align-middle">Description</th>
                  <td>
                    <input
                      type="text"
                      name="description"
                      value={@create_form["description"]}
                      placeholder="Optional description"
                      class="input input-bordered w-full"
                    />
                  </td>
                </tr>
                <tr>
                  <th class="align-middle">Source</th>
                  <td>
                    <input
                      type="text"
                      name="source"
                      value={@create_form["source"]}
                      placeholder="Optional source identifier"
                      class="input input-bordered w-full"
                    />
                  </td>
                </tr>
              </tbody>
            </table>
            <div class="modal-action">
              <button type="button" phx-click="close_create_modal" class="btn">Cancel</button>
              <button
                type="submit"
                class={"btn btn-primary #{if @create_saving, do: "loading"}"}
                disabled={@create_saving}
              >
                Create
              </button>
            </div>
          </form>
        </div>
        <div class="modal-backdrop" phx-click="close_create_modal"></div>
      </div>
    <% end %>
    </.admin_layout>
    """
  end
end