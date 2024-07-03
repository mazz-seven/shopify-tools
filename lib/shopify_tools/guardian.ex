defmodule ShopifyTools.Guardian do
  require Logger

  use Guardian,
    otp_app: :engine,
    issuer: "AMOS",
    secret_key: "eeca20e844ae5cc4471d0c8307eb8518",
    allowed_algos: ["HS512", "HS256"]

  def subject_for_token(%{url: url} = shop, _claims) do
    Logger.info("subject_for_token #{inspect(shop)}")
    # You can use any value for the subject of your token but
    # it should be useful in retrieving the resource later, see
    # how it is being used on `resource_from_claims/1` function.
    # A unique `id` is a good subject, a non-unique email address
    # is a poor subject.
    {:ok, url}
  end

  def subject_for_token(shop, _) do
    {:error, :url_not_found}
  end

  @doc """
  Since app bridge tokens are only short lived, we generate
  a new longer lived token for the rest of the session
  lifetime. These tokens contain the shop url in the
  "sub" claim.
  """
  def resource_from_claims(%{"dest" => "https://" <> shop_url} = claims) do
    Logger.info("resource_from_claims #{inspect(shop_url)}")
    shop = %{url: shop_url}
    {:ok, shop}
  end

  def resource_from_claims(%{"sub" => shop_url} = claims) do
    Logger.info("resource_from_claims/sub #{inspect(shop_url)}")
    shop = %{url: shop_url}
    {:ok, shop}
  end

  def resource_from_claims(claims) do
    {:error, :reason_for_error}
  end
end
