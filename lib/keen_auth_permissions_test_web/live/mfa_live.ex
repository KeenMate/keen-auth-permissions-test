defmodule KeenAuthPermissionsTestWeb.MfaLive do
  use KeenAuthPermissionsTestWeb, :live_view

  require Logger

  alias KeenAuthPermissions.Mfa
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
         page_title: "MFA",
         user: user,
         ctx: ctx,
         error: nil,
         auth_blocked: false,
         auth_warning: false,
         auth_warning_message: "",
         active_tab: :status,
         # Status tab
         target_user_id: to_string(user.user_id),
         mfa_status: [],
         mfa_required: nil,
         status_loading: true,
         # Enroll modal
         show_enroll_modal: false,
         enroll_form: %{"mfa_type_code" => "totp", "secret_encrypted" => ""},
         enroll_saving: false,
         enroll_error: nil,
         enroll_result: nil,
         # Confirm modal
         show_confirm_modal: false,
         confirm_type: nil,
         confirm_saving: false,
         confirm_error: nil,
         # Reset result modal
         show_reset_result: false,
         reset_recovery_codes: [],
         # Policies tab
         policies: [],
         policies_loading: false,
         policies_loaded: false,
         show_create_policy_modal: false,
         policy_form: %{
           "tenant_id" => "",
           "user_group_id" => "",
           "target_user_id" => "",
           "mfa_required" => "true"
         },
         policy_saving: false,
         policy_error: nil,
         # Login tab
         login_loaded: false,
         verify_form: %{"email" => "", "password_hash" => ""},
         verify_result: nil,
         verify_error: nil,
         verify_loading: false,
         failure_form: %{"target_user_id" => "", "email" => ""},
         failure_result: nil,
         failure_error: nil,
         failure_loading: false
       )
       |> load_status()}
    end
  end

  @impl true
  def handle_info({:sse_event, event, payload}, socket) do
    {:noreply, AuthEventHandler.handle_sse_event(socket, event, payload, &load_status/1)}
  end

  @impl true
  def handle_event("dismiss_auth_warning", _params, socket) do
    {:noreply, assign(socket, auth_warning: false, auth_warning_message: "")}
  end

  # ============================================================================
  # Tab Navigation
  # ============================================================================

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)
    socket = assign(socket, active_tab: tab)

    socket =
      case tab do
        :policies ->
          if socket.assigns.policies_loaded,
            do: socket,
            else: load_policies(socket)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  # ============================================================================
  # Status Tab — Load & Refresh
  # ============================================================================

  def handle_event("refresh_status", _params, socket) do
    {:noreply,
     socket
     |> assign(status_loading: true)
     |> load_status()}
  end

  def handle_event("status_user_change", %{"target_user_id" => tid}, socket) do
    {:noreply, assign(socket, target_user_id: tid)}
  end

  def handle_event("load_status_for_user", %{"target_user_id" => tid}, socket) do
    {:noreply,
     socket
     |> assign(target_user_id: tid, status_loading: true)
     |> load_status()}
  end

  # ============================================================================
  # Enroll
  # ============================================================================

  def handle_event("open_enroll_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_enroll_modal: true,
       enroll_form: %{"mfa_type_code" => "totp", "secret_encrypted" => ""},
       enroll_error: nil,
       enroll_result: nil
     )}
  end

  def handle_event("close_enroll_modal", _params, socket) do
    {:noreply, assign(socket, show_enroll_modal: false, enroll_error: nil, enroll_result: nil)}
  end

  def handle_event("enroll_form_change", params, socket) do
    {:noreply, assign(socket, enroll_form: params)}
  end

  def handle_event("enroll_mfa", params, socket) do
    %{ctx: ctx, target_user_id: tid} = socket.assigns
    target = parse_int(tid)
    type_code = params["mfa_type_code"] || "totp"
    secret = params["secret_encrypted"] || ""

    if is_nil(target) do
      {:noreply, assign(socket, enroll_error: "Invalid target user ID")}
    else
      socket = assign(socket, enroll_saving: true, enroll_error: nil)

      case Mfa.enroll(ctx, target, type_code, secret) do
        {:ok, result} ->
          {:noreply,
           socket
           |> assign(enroll_saving: false, enroll_result: result)
           |> put_flash(:info, "MFA enrolled successfully")}

        {:error, reason} ->
          Logger.error("MFA enroll failed", reason: inspect(reason))

          {:noreply,
           assign(socket,
             enroll_saving: false,
             enroll_error: "Enroll failed: #{inspect(reason)}"
           )}
      end
    end
  end

  # ============================================================================
  # Confirm Enrollment
  # ============================================================================

  def handle_event("open_confirm_modal", %{"type" => type}, socket) do
    {:noreply,
     assign(socket,
       show_confirm_modal: true,
       confirm_type: type,
       confirm_error: nil
     )}
  end

  def handle_event("close_confirm_modal", _params, socket) do
    {:noreply, assign(socket, show_confirm_modal: false, confirm_error: nil)}
  end

  def handle_event("confirm_enrollment", %{"code_is_valid" => valid}, socket) do
    %{ctx: ctx, target_user_id: tid, confirm_type: type} = socket.assigns
    target = parse_int(tid)
    code_valid = valid == "true"

    socket = assign(socket, confirm_saving: true, confirm_error: nil)

    case Mfa.confirm_enrollment(ctx, target, type, code_valid) do
      :ok ->
        {:noreply,
         socket
         |> assign(show_confirm_modal: false, confirm_saving: false, status_loading: true)
         |> put_flash(:info, "MFA enrollment confirmed")
         |> load_status()}

      {:error, reason} ->
        Logger.error("MFA confirm failed", reason: inspect(reason))

        {:noreply,
         assign(socket,
           confirm_saving: false,
           confirm_error: "Confirm failed: #{inspect(reason)}"
         )}
    end
  end

  # ============================================================================
  # Disable MFA
  # ============================================================================

  def handle_event("disable_mfa", %{"type" => type}, socket) do
    %{ctx: ctx, target_user_id: tid} = socket.assigns
    target = parse_int(tid)

    case Mfa.disable(ctx, target, type) do
      :ok ->
        {:noreply,
         socket
         |> assign(status_loading: true)
         |> put_flash(:info, "MFA disabled for #{type}")
         |> load_status()}

      {:error, reason} ->
        Logger.error("MFA disable failed", reason: inspect(reason))
        {:noreply, put_flash(socket, :error, "Disable failed: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # Reset MFA
  # ============================================================================

  def handle_event("reset_mfa", %{"type" => type}, socket) do
    %{ctx: ctx, target_user_id: tid} = socket.assigns
    target = parse_int(tid)

    case Mfa.reset(ctx, target, type) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(
           show_reset_result: true,
           reset_recovery_codes: result.recovery_codes || [],
           status_loading: true
         )
         |> put_flash(:info, "MFA reset successfully")
         |> load_status()}

      {:error, reason} ->
        Logger.error("MFA reset failed", reason: inspect(reason))
        {:noreply, put_flash(socket, :error, "Reset failed: #{inspect(reason)}")}
    end
  end

  def handle_event("close_reset_result", _params, socket) do
    {:noreply, assign(socket, show_reset_result: false, reset_recovery_codes: [])}
  end

  # ============================================================================
  # Policies Tab
  # ============================================================================

  def handle_event("open_create_policy_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_create_policy_modal: true,
       policy_form: %{
         "tenant_id" => "",
         "user_group_id" => "",
         "target_user_id" => "",
         "mfa_required" => "true"
       },
       policy_error: nil
     )}
  end

  def handle_event("close_create_policy_modal", _params, socket) do
    {:noreply, assign(socket, show_create_policy_modal: false, policy_error: nil)}
  end

  def handle_event("policy_form_change", params, socket) do
    {:noreply, assign(socket, policy_form: params)}
  end

  def handle_event("create_policy", params, socket) do
    %{ctx: ctx} = socket.assigns

    tenant_id = parse_int_or_nil(params["tenant_id"])
    user_group_id = parse_int_or_nil(params["user_group_id"])
    target_user_id = parse_int_or_nil(params["target_user_id"])
    mfa_required = params["mfa_required"] == "true"

    socket = assign(socket, policy_saving: true, policy_error: nil)

    case Mfa.create_policy(ctx, tenant_id, user_group_id, target_user_id, mfa_required) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> assign(show_create_policy_modal: false, policy_saving: false)
         |> put_flash(:info, "MFA policy created")
         |> load_policies()}

      {:error, reason} ->
        Logger.error("Create MFA policy failed", reason: inspect(reason))

        {:noreply,
         assign(socket,
           policy_saving: false,
           policy_error: "Create failed: #{inspect(reason)}"
         )}
    end
  end

  def handle_event("delete_policy", %{"id" => id}, socket) do
    %{ctx: ctx} = socket.assigns
    policy_id = String.to_integer(id)

    case Mfa.delete_policy(ctx, policy_id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "MFA policy deleted")
         |> load_policies()}

      {:error, reason} ->
        Logger.error("Delete MFA policy failed", reason: inspect(reason))
        {:noreply, put_flash(socket, :error, "Delete failed: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # Login Verification Tab
  # ============================================================================

  def handle_event("verify_form_change", params, socket) do
    {:noreply, assign(socket, verify_form: params)}
  end

  def handle_event("verify_user_by_email", params, socket) do
    %{ctx: ctx} = socket.assigns
    email = String.trim(params["email"] || "")
    password_hash = params["password_hash"] || ""

    if email == "" do
      {:noreply, assign(socket, verify_error: "Email is required")}
    else
      socket = assign(socket, verify_loading: true, verify_error: nil, verify_result: nil)

      case Mfa.verify_user_by_email(ctx, email, password_hash) do
        {:ok, result} ->
          {:noreply,
           assign(socket, verify_loading: false, verify_result: result, verify_error: nil)}

        {:error, reason} ->
          Logger.error("Verify user by email failed", reason: inspect(reason))

          {:noreply,
           assign(socket,
             verify_loading: false,
             verify_error: "Verification failed: #{inspect(reason)}"
           )}
      end
    end
  end

  def handle_event("failure_form_change", params, socket) do
    {:noreply, assign(socket, failure_form: params)}
  end

  def handle_event("record_login_failure", params, socket) do
    %{ctx: ctx} = socket.assigns
    target = parse_int(params["target_user_id"])
    email = String.trim(params["email"] || "")

    cond do
      is_nil(target) ->
        {:noreply, assign(socket, failure_error: "Target User ID is required")}

      email == "" ->
        {:noreply, assign(socket, failure_error: "Email is required")}

      true ->
        socket = assign(socket, failure_loading: true, failure_error: nil, failure_result: nil)

        case Mfa.record_login_failure(ctx, target, email) do
          :ok ->
            {:noreply,
             assign(socket,
               failure_loading: false,
               failure_result: "Login failure recorded",
               failure_error: nil
             )}

          {:error, reason} ->
            Logger.error("Record login failure failed", reason: inspect(reason))

            {:noreply,
             assign(socket,
               failure_loading: false,
               failure_error: "Failed: #{inspect(reason)}"
             )}
        end
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp load_status(socket) do
    %{ctx: ctx, target_user_id: tid} = socket.assigns
    target = parse_int(tid)

    if is_nil(target) do
      assign(socket, mfa_status: [], mfa_required: nil, status_loading: false, error: nil)
    else
      status_result = Mfa.get_status(ctx, target)
      required_result = Mfa.is_required?(ctx, target, @default_tenant_id)

      socket =
        case status_result do
          {:ok, statuses} ->
            assign(socket, mfa_status: statuses, status_loading: false, error: nil)

          {:error, reason} ->
            Logger.error("Failed to load MFA status", reason: inspect(reason))

            assign(socket,
              mfa_status: [],
              status_loading: false,
              error: "Failed to load MFA status: #{inspect(reason)}"
            )
        end

      case required_result do
        {:ok, required} -> assign(socket, mfa_required: required)
        {:error, _} -> assign(socket, mfa_required: nil)
      end
    end
  end

  defp load_policies(socket) do
    %{ctx: ctx} = socket.assigns

    case Mfa.get_policies(ctx, nil, nil, nil) do
      {:ok, policies} ->
        assign(socket, policies: policies, policies_loading: false, policies_loaded: true)

      {:error, reason} ->
        Logger.error("Failed to load MFA policies", reason: inspect(reason))
        assign(socket, policies: [], policies_loading: false, policies_loaded: true)
    end
  end

  defp build_context(%User{} = user) do
    RequestContext.new(user)
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(val) when is_integer(val), do: val

  defp parse_int_or_nil(val) do
    case parse_int(val) do
      nil -> nil
      n -> n
    end
  end

  defp format_datetime(nil), do: "-"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
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
    <.admin_layout current_page={:mfa}>
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">Multi-Factor Authentication</h1>
          
          <div class="breadcrumbs text-sm">
            <ul>
              <li><a href="/">Home</a></li>
              
              <li><a href="/dashboard">Dashboard</a></li>
              
              <li>MFA</li>
            </ul>
          </div>
        </div>
        
        <%= if @error do %>
          <div class="alert alert-error mb-4"><span>{@error}</span></div>
        <% end %>
         <%!-- Tab Bar --%>
        <div role="tablist" class="tabs tabs-bordered mb-6">
          <button
            role="tab"
            class={"tab #{if @active_tab == :status, do: "tab-active"}"}
            phx-click="switch_tab"
            phx-value-tab="status"
          >
            MFA Status
          </button>
          <button
            role="tab"
            class={"tab #{if @active_tab == :policies, do: "tab-active"}"}
            phx-click="switch_tab"
            phx-value-tab="policies"
          >
            Policies
          </button>
          <button
            role="tab"
            class={"tab #{if @active_tab == :login, do: "tab-active"}"}
            phx-click="switch_tab"
            phx-value-tab="login"
          >
            Login Verification
          </button>
        </div>
         <%!-- Tab Content --%>
        <%= case @active_tab do %>
          <% :status -> %>
            <.status_tab
              target_user_id={@target_user_id}
              mfa_status={@mfa_status}
              mfa_required={@mfa_required}
              status_loading={@status_loading}
            />
          <% :policies -> %>
            <.policies_tab
              policies={@policies}
              policies_loading={@policies_loading}
            />
          <% :login -> %>
            <.login_tab
              verify_form={@verify_form}
              verify_result={@verify_result}
              verify_error={@verify_error}
              verify_loading={@verify_loading}
              failure_form={@failure_form}
              failure_result={@failure_result}
              failure_error={@failure_error}
              failure_loading={@failure_loading}
            />
        <% end %>

     <%!-- Enroll Modal --%>
    <%= if @show_enroll_modal do %>
      <div class="modal modal-open">
        <div class="modal-box w-full max-w-2xl">
          <h3 class="font-bold text-lg mb-6">Enroll MFA</h3>
          
          <%= if @enroll_error do %>
            <div class="alert alert-error mb-4"><span>{@enroll_error}</span></div>
          <% end %>
          
          <%= if @enroll_result do %>
            <div class="alert alert-success mb-4">
              <div>
                <p class="font-bold">Enrollment successful!</p>
                
                <p>MFA ID: {@enroll_result.user_mfa_id}</p>
                
                <p>Type: {@enroll_result.mfa_type_code}</p>
                
                <p>Enrolled at: {format_datetime(@enroll_result.enrolled_at)}</p>
              </div>
            </div>
            
            <%= if @enroll_result.recovery_codes && @enroll_result.recovery_codes != [] do %>
              <div class="alert alert-warning mb-4">
                <div>
                  <p class="font-bold">Recovery Codes — save these now!</p>
                  
                  <div class="grid grid-cols-2 gap-1 mt-2">
                    <%= for code <- @enroll_result.recovery_codes do %>
                      <code class="bg-base-200 px-2 py-1 rounded text-sm">{code}</code>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
            
            <div class="modal-action">
              <button phx-click="close_enroll_modal" class="btn">Close</button>
              <button
                phx-click="refresh_status"
                class="btn btn-primary"
                phx-click="close_enroll_modal"
              >
                Done & Refresh
              </button>
            </div>
          <% else %>
            <form phx-submit="enroll_mfa" phx-change="enroll_form_change">
              <table class="table">
                <tbody>
                  <tr>
                    <th class="w-48 align-middle">Target User ID</th>
                    
                    <td>
                      <input
                        type="text"
                        value={@target_user_id}
                        class="input input-bordered w-full"
                        disabled
                      />
                    </td>
                  </tr>
                  
                  <tr>
                    <th class="align-middle">MFA Type</th>
                    
                    <td>
                      <select
                        name="mfa_type_code"
                        class="select select-bordered w-full"
                      >
                        <option value="totp" selected={@enroll_form["mfa_type_code"] == "totp"}>
                          TOTP (Time-based One-Time Password)
                        </option>
                      </select>
                    </td>
                  </tr>
                  
                  <tr>
                    <th class="align-middle">Secret (encrypted)</th>
                    
                    <td>
                      <input
                        type="text"
                        name="secret_encrypted"
                        value={@enroll_form["secret_encrypted"]}
                        placeholder="Encrypted TOTP secret"
                        class="input input-bordered w-full"
                        required
                      />
                    </td>
                  </tr>
                </tbody>
              </table>
              
              <div class="modal-action">
                <button type="button" phx-click="close_enroll_modal" class="btn">Cancel</button>
                <button
                  type="submit"
                  class={"btn btn-primary #{if @enroll_saving, do: "loading"}"}
                  disabled={@enroll_saving}
                >
                  Enroll
                </button>
              </div>
            </form>
          <% end %>
        </div>
        
        <div class="modal-backdrop" phx-click="close_enroll_modal"></div>
      </div>
    <% end %>
     <%!-- Confirm Enrollment Modal --%>
    <%= if @show_confirm_modal do %>
      <div class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg mb-6">Confirm MFA Enrollment ({@confirm_type})</h3>
          
          <%= if @confirm_error do %>
            <div class="alert alert-error mb-4"><span>{@confirm_error}</span></div>
          <% end %>
          
          <p class="mb-4">In a real app, the user would enter their TOTP code here.
            For testing, choose whether the code should be treated as valid.</p>
          
          <div class="modal-action">
            <button type="button" phx-click="close_confirm_modal" class="btn">Cancel</button>
            <button
              phx-click="confirm_enrollment"
              phx-value-code_is_valid="false"
              class={"btn btn-error #{if @confirm_saving, do: "loading"}"}
              disabled={@confirm_saving}
            >
              Simulate Invalid
            </button>
            <button
              phx-click="confirm_enrollment"
              phx-value-code_is_valid="true"
              class={"btn btn-success #{if @confirm_saving, do: "loading"}"}
              disabled={@confirm_saving}
            >
              Simulate Valid
            </button>
          </div>
        </div>
        
        <div class="modal-backdrop" phx-click="close_confirm_modal"></div>
      </div>
    <% end %>
     <%!-- Reset Recovery Codes Modal --%>
    <%= if @show_reset_result do %>
      <div class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg mb-4">New Recovery Codes</h3>
          
          <div class="alert alert-warning mb-4">
            <p class="font-bold">Save these codes — they won't be shown again!</p>
          </div>
          
          <div class="grid grid-cols-2 gap-2">
            <%= for code <- @reset_recovery_codes do %>
              <code class="bg-base-200 px-3 py-2 rounded text-sm text-center">{code}</code>
            <% end %>
          </div>
          
          <%= if @reset_recovery_codes == [] do %>
            <p class="text-base-content/50 text-center py-4">No recovery codes returned</p>
          <% end %>
          
          <div class="modal-action">
            <button phx-click="close_reset_result" class="btn btn-primary">Done</button>
          </div>
        </div>
        
        <div class="modal-backdrop" phx-click="close_reset_result"></div>
      </div>
    <% end %>
     <%!-- Create Policy Modal --%>
    <%= if @show_create_policy_modal do %>
      <div class="modal modal-open">
        <div class="modal-box w-full max-w-2xl">
          <h3 class="font-bold text-lg mb-6">Create MFA Policy</h3>
          
          <%= if @policy_error do %>
            <div class="alert alert-error mb-4"><span>{@policy_error}</span></div>
          <% end %>
          
          <form phx-submit="create_policy" phx-change="policy_form_change">
            <table class="table">
              <tbody>
                <tr>
                  <th class="w-48 align-middle">Tenant ID</th>
                  
                  <td>
                    <input
                      type="text"
                      name="tenant_id"
                      value={@policy_form["tenant_id"]}
                      placeholder="Optional — leave blank for all"
                      class="input input-bordered w-full"
                    />
                  </td>
                </tr>
                
                <tr>
                  <th class="align-middle">User Group ID</th>
                  
                  <td>
                    <input
                      type="text"
                      name="user_group_id"
                      value={@policy_form["user_group_id"]}
                      placeholder="Optional — leave blank for all"
                      class="input input-bordered w-full"
                    />
                  </td>
                </tr>
                
                <tr>
                  <th class="align-middle">Target User ID</th>
                  
                  <td>
                    <input
                      type="text"
                      name="target_user_id"
                      value={@policy_form["target_user_id"]}
                      placeholder="Optional — leave blank for all"
                      class="input input-bordered w-full"
                    />
                  </td>
                </tr>
                
                <tr>
                  <th class="align-middle">MFA Required</th>
                  
                  <td>
                    <label class="label cursor-pointer justify-start gap-3">
                      <input
                        type="checkbox"
                        name="mfa_required"
                        value="true"
                        checked={@policy_form["mfa_required"] == "true"}
                        class="checkbox checkbox-primary"
                      /> <span>Require MFA</span>
                    </label>
                  </td>
                </tr>
              </tbody>
            </table>
            
            <div class="modal-action">
              <button type="button" phx-click="close_create_policy_modal" class="btn">Cancel</button>
              <button
                type="submit"
                class={"btn btn-primary #{if @policy_saving, do: "loading"}"}
                disabled={@policy_saving}
              >
                Create Policy
              </button>
            </div>
          </form>
        </div>
        <div class="modal-backdrop" phx-click="close_create_policy_modal"></div>
      </div>
    <% end %>
    </.admin_layout>
    """
  end

  # ============================================================================
  # Tab Components
  # ============================================================================

  defp status_tab(assigns) do
    ~H"""
    <%!-- User selector --%>
    <div class="card bg-base-100 shadow-xl mb-4">
      <div class="card-body">
        <form
          phx-submit="load_status_for_user"
          phx-change="status_user_change"
          class="flex gap-4 items-end"
        >
          <div class="form-control flex-1">
            <label class="label"><span class="label-text">Target User ID</span></label>
            <input
              type="text"
              name="target_user_id"
              value={@target_user_id}
              placeholder="User ID to check"
              class="input input-bordered"
            />
          </div>
           <button type="submit" class="btn btn-primary">Load Status</button>
          <button type="button" phx-click="refresh_status" class="btn btn-ghost">Refresh</button>
          <button type="button" phx-click="open_enroll_modal" class="btn btn-success">
            Enroll MFA
          </button>
        </form>
      </div>
    </div>
     <%!-- MFA Required badge --%>
    <div class="mb-4">
      <%= case @mfa_required do %>
        <% true -> %>
          <span class="badge badge-warning badge-lg gap-2">MFA Required for this user</span>
        <% false -> %>
          <span class="badge badge-ghost badge-lg gap-2">MFA not required for this user</span>
        <% nil -> %>
          <span class="badge badge-ghost badge-lg gap-2">MFA requirement unknown</span>
      <% end %>
    </div>
     <%!-- Status table --%>
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title">Enrollment Status</h2>
        
        <%= if @status_loading do %>
          <div class="flex justify-center py-8">
            <span class="loading loading-spinner loading-lg"></span>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table table-zebra">
              <thead>
                <tr>
                  <th class="w-1">Actions</th>
                  <th>MFA ID</th>
                  <th>Type</th>
                  <th>Enabled</th>
                  <th>Confirmed</th>
                  <th>Enrolled At</th>
                  <th>Confirmed At</th>
                  <th>Recovery Codes Left</th>
                </tr>
              </thead>
              
              <tbody>
                <%= for s <- @mfa_status do %>
                  <tr>
                    <td>
                      <div class="flex gap-1">
                        <%= if s.is_enabled && !s.is_confirmed do %>
                          <.action_icon
                            icon="hero-check-circle"
                            color="green"
                            tooltip="Confirm"
                            phx-click="open_confirm_modal"
                            phx-value-type={s.mfa_type_code}
                          />
                        <% end %>
                        <%= if s.is_enabled do %>
                          <.action_icon
                            icon="hero-arrow-path"
                            color="yellow"
                            tooltip="Reset"
                            confirm="Reset MFA? This will generate new recovery codes."
                            phx-click="reset_mfa"
                            phx-value-type={s.mfa_type_code}
                          />
                          <.action_icon
                            icon="hero-no-symbol"
                            color="red"
                            tooltip="Disable"
                            confirm="Disable MFA for this user?"
                            phx-click="disable_mfa"
                            phx-value-type={s.mfa_type_code}
                          />
                        <% end %>
                      </div>
                    </td>
                    <td>{s.user_mfa_id}</td>
                    <td><span class="badge badge-info">{s.mfa_type_code}</span></td>
                    <td>
                      <%= if s.is_enabled do %>
                        <span class="badge badge-success">Yes</span>
                      <% else %>
                        <span class="badge badge-error">No</span>
                      <% end %>
                    </td>
                    <td>
                      <%= if s.is_confirmed do %>
                        <span class="badge badge-success">Yes</span>
                      <% else %>
                        <span class="badge badge-warning">No</span>
                      <% end %>
                    </td>
                    <td class="text-sm">{format_datetime(s.enrolled_at)}</td>
                    <td class="text-sm">{format_datetime(s.confirmed_at)}</td>
                    <td>{s.recovery_codes_remaining}</td>
                  </tr>
                <% end %>

                <%= if Enum.empty?(@mfa_status) do %>
                  <tr>
                    <td colspan="8" class="text-center text-base-content/50 py-8">
                      No MFA enrollments found
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp policies_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <div class="flex justify-between items-center mb-4">
          <h2 class="card-title">MFA Policies</h2>
          
          <button phx-click="open_create_policy_modal" class="btn btn-primary">
            New Policy
          </button>
        </div>
        
        <%= if @policies_loading do %>
          <div class="flex justify-center py-8">
            <span class="loading loading-spinner loading-lg"></span>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table table-zebra">
              <thead>
                <tr>
                  <th class="w-1">Actions</th>
                  <th>Policy ID</th>
                  <th>Tenant ID</th>
                  <th>Group ID</th>
                  <th>User ID</th>
                  <th>Required</th>
                  <th>Created At</th>
                  <th>Created By</th>
                </tr>
              </thead>
              
              <tbody>
                <%= for p <- @policies do %>
                  <tr>
                    <td>
                      <.action_icon
                        icon="hero-trash"
                        color="red"
                        tooltip="Delete policy"
                        confirm="Delete this MFA policy?"
                        phx-click="delete_policy"
                        phx-value-id={p.mfa_policy_id}
                      />
                    </td>
                    <td>{p.mfa_policy_id}</td>
                    <td>{p.tenant_id || "-"}</td>
                    <td>{p.user_group_id || "-"}</td>
                    <td>{p.user_id || "-"}</td>
                    <td>
                      <%= if p.mfa_required do %>
                        <span class="badge badge-warning">Yes</span>
                      <% else %>
                        <span class="badge badge-ghost">No</span>
                      <% end %>
                    </td>
                    <td class="text-sm">{format_datetime(p.created_at)}</td>
                    <td>{p.created_by || "-"}</td>
                  </tr>
                <% end %>
                
                <%= if Enum.empty?(@policies) do %>
                  <tr>
                    <td colspan="8" class="text-center text-base-content/50 py-8">
                      No MFA policies found
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp login_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <%!-- Verify by Email --%>
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title">Verify User by Email</h2>
          
          <p class="text-sm text-base-content/70 mb-4">
            Calls <code>auth.verify_user_by_email</code>
            — authenticates a user by email and password hash.
          </p>
          
          <%= if @verify_error do %>
            <div class="alert alert-error mb-4"><span>{@verify_error}</span></div>
          <% end %>
          
          <form phx-submit="verify_user_by_email" phx-change="verify_form_change">
            <div class="form-control mb-3">
              <label class="label"><span class="label-text">Email</span></label>
              <input
                type="email"
                name="email"
                value={@verify_form["email"]}
                placeholder="user@example.com"
                class="input input-bordered w-full"
                required
              />
            </div>
            
            <div class="form-control mb-4">
              <label class="label"><span class="label-text">Password Hash</span></label>
              <input
                type="text"
                name="password_hash"
                value={@verify_form["password_hash"]}
                placeholder="bcrypt / argon2 hash"
                class="input input-bordered w-full"
                required
              />
            </div>
            
            <button
              type="submit"
              class={"btn btn-primary w-full #{if @verify_loading, do: "loading"}"}
              disabled={@verify_loading}
            >
              Verify
            </button>
          </form>
          
          <%= if @verify_result do %>
            <div class="divider">Result</div>
            
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <tbody>
                  <tr>
                    <th>User ID</th>
                    <td>{@verify_result.user_id}</td>
                  </tr>
                  
                  <tr>
                    <th>Code</th>
                    <td>{@verify_result.code}</td>
                  </tr>
                  
                  <tr>
                    <th>UUID</th>
                    <td><code class="text-xs">{@verify_result.uuid}</code></td>
                  </tr>
                  
                  <tr>
                    <th>Username</th>
                    <td>{@verify_result.username}</td>
                  </tr>
                  
                  <tr>
                    <th>Email</th>
                    <td>{@verify_result.email}</td>
                  </tr>
                  
                  <tr>
                    <th>Display Name</th>
                    <td>{@verify_result.display_name}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>
       <%!-- Record Login Failure --%>
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title">Record Login Failure</h2>
          
          <p class="text-sm text-base-content/70 mb-4">
            Calls <code>auth.record_login_failure</code> — tracks failed logins for auto-lockout.
          </p>
          
          <%= if @failure_error do %>
            <div class="alert alert-error mb-4"><span>{@failure_error}</span></div>
          <% end %>
          
          <form phx-submit="record_login_failure" phx-change="failure_form_change">
            <div class="form-control mb-3">
              <label class="label"><span class="label-text">Target User ID</span></label>
              <input
                type="text"
                name="target_user_id"
                value={@failure_form["target_user_id"]}
                placeholder="User ID"
                class="input input-bordered w-full"
                required
              />
            </div>
            
            <div class="form-control mb-4">
              <label class="label"><span class="label-text">Email</span></label>
              <input
                type="email"
                name="email"
                value={@failure_form["email"]}
                placeholder="user@example.com"
                class="input input-bordered w-full"
                required
              />
            </div>
            
            <button
              type="submit"
              class={"btn btn-warning w-full #{if @failure_loading, do: "loading"}"}
              disabled={@failure_loading}
            >
              Record Failure
            </button>
          </form>
          
          <%= if @failure_result do %>
            <div class="divider">Result</div>
            
            <div class="alert alert-success"><span>{@failure_result}</span></div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
