defmodule ShopifyTools.Plug do
  import Plug.Conn

  require Logger

  @type shop :: %{access_token: String.t(), scope: String.t(), url: String.t()}

  defdelegate session(conn, opts), to: ShopifyTools.Plug.Session
  defdelegate set_frame_ancestors(conn, opts), to: ShopifyTools.Plug.SetCspHeader

  @doc """
   ## Options

   * client_id
   * client_secret
  """
  def shopify_app(conn, opts) do
    conn
    |> put_private(:shopify_tools, %{
      client_id: Keyword.fetch!(opts, :client_id),
      client_secret: Keyword.fetch!(opts, :client_secret)
    })
  end

  def fetch_client_id(%Plug.Conn{private: private}) do
    case Map.fetch(private, :shopify_tools) do
      {:ok, app} ->
        app.client_id

      :error ->
        raise ArgumentError, "cannot fetch client_id without a configured shopify_app plug"
    end
  end

  def fetch_client_secret(%Plug.Conn{private: private}) do
    case Map.fetch(private, :shopify_tools) do
      {:ok, app} ->
        app.client_secret

      :error ->
        raise ArgumentError, "cannot fetch client_secret without a configured shopify_app plug"
    end
  end

  @spec put_shop(
          conn :: Plug.Conn.t(),
          shop :: shop(),
          host :: String.t(),
          locale :: Gettext.locale()
        ) :: Plug.Conn.t()
  def put_shop(conn, shop, host, locale \\ "en") do
    # Gettext.put_locale(locale)

    {:ok, token, claims} =
      ShopifyTools.Guardian.encode_and_sign(shop, %{"loc" => locale, "host" => host})

    conn
    |> Guardian.Plug.put_current_token(shop)
    |> Guardian.Plug.put_current_claims(claims)
    |> Guardian.Plug.put_current_token(token)
    |> Plug.Conn.put_private(
      :shopify_tools,
      Map.merge(conn.private.shopify_tools, %{shop: shop, host: host})
    )
  end

  @doc """
  Get current request shop resource for give `conn`.

  Available in all requests which have passed through a `:shopify_*` pipeline.

  ## Examples:

      iex> current_shop(conn)
      shop

  """
  @spec current_shop(conn :: Plug.Conn.t()) :: shop()
  def current_shop(%Plug.Conn{private: %{shopify_tools: %{shop: shop}}}), do: shop
  def current_shop(_), do: nil
end
