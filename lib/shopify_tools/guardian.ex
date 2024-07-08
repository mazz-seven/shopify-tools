defmodule ShopifyTools.Guardian do
  require Logger

  # AppBridge frequently sends future `nbf`, and it causes `{:error, :token_not_yet_valid}`.
  # Accept few seconds clock skew to avoid this error.
  # 
  # see: https://github.com/Shopify/shopify_python_api/blob/master/shopify/session_token.py#L58-L60
  @allowed_drift Application.compile_env(:shopify_tools, :allowed_drift, 10_000)

  use Guardian,
    otp_app: :engine,
    issuer: {Application, :get_env, [:shopify_tools, :app]},
    secret_key: {Application, :get_env, [:shopify_tools, :client_secret]},
    allowed_algos: ["HS512", "HS256"],
    allowed_drift: @allowed_drift

  def subject_for_token(%{url: url} = shop, _claims) do
    Logger.info("subject_for_token #{inspect(shop)}")
    # You can use any value for the subject of your token but
    # it should be useful in retrieving the resource later, see
    # how it is being used on `resource_from_claims/1` function.
    # A unique `id` is a good subject, a non-unique email address
    # is a poor subject.
    {:ok, url}
  end

  def subject_for_token(_shop, _) do
    {:error, :url_not_found}
  end

  @doc """
  Since app bridge tokens are only short lived, we generate
  a new longer lived token for the rest of the session
  lifetime. These tokens contain the shop url in the
  "sub" claim.
  """
  def resource_from_claims(%{"dest" => "https://" <> shop_url} = _claims) do
    Logger.info("resource_from_claims #{inspect(shop_url)}")
    shop = %{url: shop_url}
    {:ok, shop}
  end

  def resource_from_claims(%{"sub" => shop_url} = _claims) do
    Logger.info("resource_from_claims/sub #{inspect(shop_url)}")
    shop = %{url: shop_url}
    {:ok, shop}
  end

  def resource_from_claims(_claims) do
    {:error, :reason_for_error}
  end
end
