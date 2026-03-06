defmodule KeenAuthPermissionsTestWeb.MfaSetupLive do
  use KeenAuthPermissionsTestWeb, :live_view

  require Logger

  alias KeenAuthPermissions.Mfa
  alias KeenAuthPermissions.RequestContext

  @issuer "KeenAuthTest"

  @impl true
  def mount(_params, session, socket) do
    user_id = session["mfa_setup_user_id"]

    if is_nil(user_id) do
      {:ok, push_navigate(socket, to: "/login")}
    else
      ctx = RequestContext.service_ctx(:token_manager)

      {:ok,
       socket
       |> assign(
         page_title: "Set Up MFA",
         user_id: user_id,
         ctx: ctx,
         step: :enroll,
         secret: nil,
         secret_base32: nil,
         qr_svg: nil,
         recovery_codes: [],
         totp_code: "",
         error: nil,
         loading: false
       )}
    end
  end

  # ============================================================================
  # Events
  # ============================================================================

  @impl true
  def handle_event("begin_enroll", _params, socket) do
    %{ctx: ctx, user_id: user_id} = socket.assigns
    secret = NimbleTOTP.secret()
    secret_base32 = Base.encode32(secret, padding: false)
    socket = assign(socket, loading: true, error: nil)

    case Mfa.enroll(ctx, user_id, "totp", secret_base32) do
      {:ok, result} ->
        label = "#{@issuer}:User#{user_id}"
        uri = NimbleTOTP.otpauth_uri(label, secret, issuer: @issuer)
        qr_svg = uri |> EQRCode.encode() |> EQRCode.svg(width: 250)

        codes =
          if is_list(result.recovery_codes), do: result.recovery_codes, else: []

        {:noreply,
         assign(socket,
           loading: false,
           secret: secret,
           secret_base32: secret_base32,
           qr_svg: qr_svg,
           recovery_codes: codes,
           step: :recovery_codes
         )}

      {:error, reason} ->
        Logger.error("MFA enroll failed", reason: inspect(reason))
        {:noreply, assign(socket, loading: false, error: "Enrollment failed: #{inspect(reason)}")}
    end
  end

  def handle_event("codes_saved", _params, socket) do
    {:noreply, assign(socket, step: :confirm, error: nil, totp_code: "")}
  end

  def handle_event("verify_code", %{"totp_code" => code}, socket) do
    %{ctx: ctx, user_id: user_id, secret: secret} = socket.assigns
    code = String.trim(code)
    socket = assign(socket, loading: true, error: nil, totp_code: code)

    code_valid = NimbleTOTP.valid?(secret, code)

    case Mfa.confirm_enrollment(ctx, user_id, "totp", code_valid) do
      :ok ->
        if code_valid do
          {:noreply, assign(socket, loading: false, step: :done)}
        else
          {:noreply,
           assign(socket,
             loading: false,
             totp_code: "",
             error: "Invalid code. Check your authenticator and try again."
           )}
        end

      {:error, reason} ->
        Logger.error("MFA confirm failed", reason: inspect(reason))

        {:noreply,
         assign(socket, loading: false, error: "Confirmation failed: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 flex items-center justify-center p-4">
      <div class="card bg-base-100 w-full max-w-lg shadow-2xl">
        <div class="card-body">
          <h1 class="card-title text-2xl justify-center mb-4">Set Up Two-Factor Authentication</h1>

          <%= if @error do %>
            <div class="alert alert-error mb-4"><span>{@error}</span></div>
          <% end %>

          {render_step(assigns)}

          <div class="divider"></div>

          <div class="text-center">
            <a href="/login" class="btn btn-ghost btn-sm">Skip</a>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_step(%{step: :enroll} = assigns) do
    ~H"""
    <div class="text-center space-y-4">
      <p class="text-base-content/70">
        Your account requires two-factor authentication. Click below to begin setup.
      </p>
      <button phx-click="begin_enroll" class="btn btn-primary w-full" disabled={@loading}>
        {if @loading, do: "Setting up...", else: "Begin Setup"}
      </button>
    </div>
    """
  end

  defp render_step(%{step: :recovery_codes} = assigns) do
    ~H"""
    <div class="space-y-4">
      <p class="text-base-content/70 text-sm">
        Save these recovery codes in a secure place. You can use them to access your account
        if you lose your authenticator device.
      </p>

      <div class="grid grid-cols-2 gap-2">
        <%= for code <- @recovery_codes do %>
          <div class="font-mono text-sm bg-base-200 rounded px-3 py-2 text-center">{code}</div>
        <% end %>
      </div>

      <%= if @recovery_codes == [] do %>
        <div class="text-base-content/50 text-sm italic text-center">
          No recovery codes returned.
        </div>
      <% end %>

      <button phx-click="codes_saved" class="btn btn-primary w-full">
        I've Saved My Codes
      </button>
    </div>
    """
  end

  defp render_step(%{step: :confirm} = assigns) do
    ~H"""
    <div class="space-y-4">
      <p class="text-base-content/70 text-sm">
        Scan this QR code with your authenticator app (Microsoft Authenticator, Google Authenticator, etc.),
        then enter the 6-digit code below.
      </p>

      <div class="flex justify-center">
        {Phoenix.HTML.raw(@qr_svg)}
      </div>

      <div class="bg-base-200 rounded p-3">
        <p class="text-xs text-base-content/50 mb-1">Can't scan? Enter this key manually:</p>
        <p class="font-mono text-sm break-all select-all">{@secret_base32}</p>
      </div>

      <form phx-submit="verify_code" class="space-y-3">
        <div class="form-control">
          <label class="label" for="totp_code">
            <span class="label-text">6-digit code</span>
          </label>
          <input
            type="text"
            name="totp_code"
            id="totp_code"
            value={@totp_code}
            placeholder="000000"
            class="input input-bordered w-full text-center font-mono text-lg tracking-widest"
            maxlength="6"
            inputmode="numeric"
            pattern="[0-9]{6}"
            autocomplete="one-time-code"
            required
          />
        </div>
        <button type="submit" class="btn btn-primary w-full" disabled={@loading}>
          {if @loading, do: "Verifying...", else: "Verify & Activate"}
        </button>
      </form>
    </div>
    """
  end

  defp render_step(%{step: :done} = assigns) do
    ~H"""
    <div class="text-center space-y-4">
      <div class="text-success text-5xl">&#10003;</div>
      <p class="text-lg font-semibold">Two-factor authentication is enabled!</p>
      <p class="text-base-content/70 text-sm">
        Your account is now secured with MFA. You can sign in.
      </p>
      <a href="/login" class="btn btn-primary w-full">Continue to Sign In</a>
    </div>
    """
  end
end
