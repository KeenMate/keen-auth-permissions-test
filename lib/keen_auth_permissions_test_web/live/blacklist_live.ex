defmodule KeenAuthPermissionsTestWeb.BlacklistLive do
  use KeenAuthPermissionsTestWeb, :live_view
  require Logger
  alias KeenAuthPermissions.Blacklist
  alias KeenAuthPermissions.RequestContext
  alias KeenAuthPermissions.User
  alias KeenAuthPermissionsTestWeb.AuthEventHandler
  @default_tenant_id 1
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
         page_title: "Blacklist",
         user: user,
         ctx: ctx,
         entries: [],
         search_text: "",
         reason_filter: "",
         loading: true,
         error: nil,
         page: 1,
         page_size: 20,
         total_items: 0,
         auth_blocked: false,
         auth_warning: false,
         auth_warning_message: "",
         # Add modal
         show_add_modal: false,
         add_form: %{
           "username" => "",
           "provider_code" => "",
           "provider_uid" => "",
           "provider_oid" => "",
           "reason" => "",
           "notes" => ""
         },
         add_saving: false,
         add_error: nil
       )
       |> load_entries()}
    end
  end
  @impl true
  def handle_info({:sse_event, event, payload}, socket) do
    {:noreply, AuthEventHandler.handle_sse_event(socket, event, payload, &load_entries/1)}
  end
  @impl true
  def handle_event("dismiss_auth_warning", _params, socket) do
    {:noreply, assign(socket, auth_warning: false, auth_warning_message: "")}
  end
  # ============================================================================
  # Search / Filter
  # ============================================================================
  def handle_event("search", params, socket) do
    search_text = params["search"] || ""
    reason_filter = params["reason"] || ""
    {:noreply,
     socket
     |> assign(search_text: search_text, reason_filter: reason_filter, page: 1, loading: true)
     |> load_entries()}
  end
  def handle_event("search_change", params, socket) do
    {:noreply,
     assign(socket, search_text: params["search"] || "", reason_filter: params["reason"] || "")}
  end
  def handle_event("go_to_page", %{"page" => page}, socket) do
    {:noreply,
     socket
     |> assign(page: String.to_integer(page), loading: true)
     |> load_entries()}
  end
  # ============================================================================
  # Add to blacklist
  # ============================================================================
  def handle_event("open_add_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_add_modal: true,
       add_form: %{
         "username" => "",
         "provider_code" => "",
         "provider_uid" => "",
         "provider_oid" => "",
         "reason" => "",
         "notes" => ""
       },
       add_error: nil
     )}
  end
  def handle_event("close_add_modal", _params, socket) do
    {:noreply, assign(socket, show_add_modal: false, add_error: nil)}
  end
  def handle_event("add_form_change", params, socket) do
    {:noreply, assign(socket, add_form: params)}
  end
  def handle_event("add_to_blacklist", params, socket) do
    %{ctx: ctx} = socket.assigns
    username = String.trim(params["username"] || "")
    provider_code = blank_to_nil(params["provider_code"])
    provider_uid = blank_to_nil(params["provider_uid"])
    provider_oid = blank_to_nil(params["provider_oid"])
    reason = blank_to_nil(params["reason"])
    notes = blank_to_nil(params["notes"])
    if username == "" do
      {:noreply, assign(socket, add_error: "Username is required")}
    else
      socket = assign(socket, add_saving: true, add_error: nil)
      case Blacklist.add(
             ctx,
             username,
             provider_code || "",
             provider_uid || "",
             provider_oid || "",
             reason,
             notes,
             @default_tenant_id
           ) do
        {:ok, _result} ->
          {:noreply,
           socket
           |> assign(show_add_modal: false, add_saving: false)
           |> put_flash(:info, "\"#{username}\" added to blacklist")
           |> load_entries()}
        {:error, reason} ->
          Logger.error("Failed to add to blacklist", reason: inspect(reason))
          {:noreply,
           assign(socket,
             add_saving: false,
             add_error: "Failed to add: #{inspect(reason)}"
           )}
      end
    end
  end
  # ============================================================================
  # Remove from blacklist
  # ============================================================================
  def handle_event("remove_entry", %{"id" => id}, socket) do
    %{ctx: ctx} = socket.assigns
    blacklist_id = String.to_integer(id)
    case Blacklist.remove(ctx, blacklist_id, @default_tenant_id) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Entry removed from blacklist")
         |> load_entries()}
      {:error, reason} ->
        Logger.error("Failed to remove from blacklist", reason: inspect(reason))
        {:noreply, put_flash(socket, :error, "Failed to remove: #{inspect(reason)}")}
    end
  end
  # ============================================================================
  # Private
  # ============================================================================
  defp load_entries(socket) do
    %{
      ctx: ctx,
      search_text: search_text,
      reason_filter: reason_filter,
      page: page,
      page_size: page_size
    } = socket.assigns
    search = if search_text == "", do: nil, else: search_text
    reason = if reason_filter == "", do: nil, else: reason_filter
    case Blacklist.search(ctx, search, reason, page, page_size, @default_tenant_id) do
      {:ok, [first | _] = entries} ->
        assign(socket,
          entries: entries,
          total_items: first.total_items,
          loading: false,
          error: nil
        )
      {:ok, []} ->
        assign(socket, entries: [], total_items: 0, loading: false, error: nil)
      {:error, reason} ->
        Logger.error("Failed to load blacklist", reason: inspect(reason))
        assign(socket,
          entries: [],
          total_items: 0,
          loading: false,
          error: "Failed to load blacklist: #{inspect(reason)}"
        )
    end
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
    <.auth_event_listener
      auth_blocked={@auth_blocked}
      auth_warning={@auth_warning}
      auth_warning_message={@auth_warning_message}
    />
    <.admin_layout current_page={:blacklist}>
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">Blacklist</h1>
          
          <div class="breadcrumbs text-sm">
            <ul>
              <li><a href="/">Home</a></li>
              
              <li><a href="/dashboard">Dashboard</a></li>
              
              <li>Blacklist</li>
            </ul>
          </div>
        </div>
        
        <%= if @error do %>
          <div class="alert alert-error mb-4"><span>{@error}</span></div>
        <% end %>
        
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <div class="flex items-center gap-4">
              <form phx-submit="search" phx-change="search_change" class="flex-1 flex gap-4">
                <input
                  type="text"
                  name="search"
                  value={@search_text}
                  placeholder="Search by username..."
                  class="input input-bordered flex-1"
                  phx-debounce="300"
                />
                <input
                  type="text"
                  name="reason"
                  value={@reason_filter}
                  placeholder="Filter by reason..."
                  class="input input-bordered w-64"
                  phx-debounce="300"
                /> <button type="submit" class="btn btn-primary">Search</button>
              </form>
               <button phx-click="open_add_modal" class="btn btn-primary">New Blacklist Entry</button>
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
                      <th class="w-1">Actions</th>
                      <th>Username</th>
                      <th>Provider</th>
                      <th>UID</th>
                      <th>OID</th>
                      <th>Reason</th>
                      <th>Notes</th>
                      <th>Created At</th>
                      <th>Created By</th>
                    </tr>
                  </thead>
                  
                  <tbody>
                    <%= for entry <- @entries do %>
                      <tr>
                        <td>
                          <.action_icon
                            icon="hero-trash"
                            color="red"
                            tooltip="Remove from blacklist"
                            confirm="Are you sure you want to remove this blacklist entry?"
                            phx-click="remove_entry"
                            phx-value-id={entry.blacklist_id}
                          />
                        </td>
                        <td><code class="text-sm">{entry.username}</code></td>
                        <td>{entry.provider_code || "-"}</td>
                        <td><code class="text-xs">{entry.provider_uid || "-"}</code></td>
                        <td><code class="text-xs">{entry.provider_oid || "-"}</code></td>
                        <td>{entry.reason || "-"}</td>
                        <td>{entry.notes || "-"}</td>
                        <td class="text-sm">{entry.created_at}</td>
                        <td>{entry.created_by || "-"}</td>
                      </tr>
                    <% end %>
                    
                    <%= if Enum.empty?(@entries) do %>
                      <tr>
                        <td colspan="9" class="text-center text-base-content/50 py-8">
                          No blacklist entries found
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
               <.pagination page={@page} page_size={@page_size} total_items={@total_items} />
            <% end %>
          </div>
        </div>

     <%!-- Add to Blacklist Modal --%>
    <%= if @show_add_modal do %>
      <div class="modal modal-open">
        <div class="modal-box w-full max-w-2xl">
          <h3 class="font-bold text-lg mb-6">Add to Blacklist</h3>
          
          <%= if @add_error do %>
            <div class="alert alert-error mb-4"><span>{@add_error}</span></div>
          <% end %>
          
          <form phx-submit="add_to_blacklist" phx-change="add_form_change">
            <table class="table">
              <tbody>
                <tr>
                  <th class="w-48 align-middle">Username</th>
                  
                  <td>
                    <input
                      type="text"
                      name="username"
                      value={@add_form["username"]}
                      placeholder="Username to blacklist"
                      class="input input-bordered w-full"
                      required
                    />
                  </td>
                </tr>
                
                <tr>
                  <th class="align-middle">Provider Code</th>
                  
                  <td>
                    <input
                      type="text"
                      name="provider_code"
                      value={@add_form["provider_code"]}
                      placeholder="e.g. azure, google"
                      class="input input-bordered w-full"
                    />
                  </td>
                </tr>
                
                <tr>
                  <th class="align-middle">Provider UID</th>
                  
                  <td>
                    <input
                      type="text"
                      name="provider_uid"
                      value={@add_form["provider_uid"]}
                      placeholder="Provider user ID"
                      class="input input-bordered w-full"
                    />
                  </td>
                </tr>
                
                <tr>
                  <th class="align-middle">Provider OID</th>
                  
                  <td>
                    <input
                      type="text"
                      name="provider_oid"
                      value={@add_form["provider_oid"]}
                      placeholder="Provider object ID"
                      class="input input-bordered w-full"
                    />
                  </td>
                </tr>
                
                <tr>
                  <th class="align-middle">Reason</th>
                  
                  <td>
                    <input
                      type="text"
                      name="reason"
                      value={@add_form["reason"]}
                      placeholder="Reason for blacklisting"
                      class="input input-bordered w-full"
                    />
                  </td>
                </tr>
                
                <tr>
                  <th class="align-middle">Notes</th>
                  
                  <td>
                    <textarea
                      name="notes"
                      placeholder="Additional notes"
                      class="textarea textarea-bordered w-full"
                      rows="3"
                    ><%= @add_form["notes"] %></textarea>
                  </td>
                </tr>
              </tbody>
            </table>
            
            <div class="modal-action">
              <button type="button" phx-click="close_add_modal" class="btn">Cancel</button>
              <button
                type="submit"
                class={"btn btn-error #{if @add_saving, do: "loading"}"}
                disabled={@add_saving}
              >
                Add to Blacklist
              </button>
            </div>
          </form>
        </div>
        <div class="modal-backdrop" phx-click="close_add_modal"></div>
      </div>
    <% end %>
    </.admin_layout>
    """
  end
end