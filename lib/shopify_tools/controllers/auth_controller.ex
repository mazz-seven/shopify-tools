defmodule ShopifyTools.AuthController do
  @moduledoc """
  You can use this module inside of another controller to handle initial iFrame load and shop installation

  Example:

  ```elixir
  defmodule MyAppWeb.AuthController do
    use MyAppWeb, :controller
    use ShopifyTools.AuthController

    # Thats it! Validation, installation are now handled for you :)
  end
  ```
  """
  @type shop :: %{access_token: String.t(), scope: String.t(), url: String.t()}

  @doc """
  An callback called after the installation is completed, the shop is
  persisted in the database and webhooks are registered. By default, this function
  redirects the user to the app within their Shopify admin panel.

  ## Example

      @impl true
      def on_install(conn, shop, oauth_state) do
        # send yourself an e-mail about shop installation

        # follow default behaviour.
        super(conn, shop, oauth_state)
      end
  """
  @callback on_install(Plug.Conn.t(), shop(), oauth_state :: String.t()) :: Plug.Conn.t()

  @doc """
  An callback called after the oauth update is completed. By default,
  this function redirects the user to the app within their Shopify admin panel.

  ## Example

      @impl true
      def on_update(conn, shop, oauth_state) do
        # do some work related to oauth_state

        # follow default behaviour.
        super(conn, shop, oauth_state)
      end
  """
  @callback on_update(Plug.Conn.t(), shop(), oauth_state :: String.t()) :: Plug.Conn.t()

  @doc """
  An optional callback which you can use to override how your app is rendered on
  initial load. If you are building a server-rendered app, you might just want
  to redirect to your index page. If you are building an externally hosted SPA,
  you probably want to redirect to the Shopify admin link for your app.

  Externally hosted SPA's will likely only hit this route on install.
  """
  @callback auth(conn :: Plug.Conn.t(), params :: Plug.Conn.params()) :: Plug.Conn.t()

  @optional_callbacks on_install: 3, on_update: 3, auth: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour ShopifyTools.AuthController

      require Logger

      @impl ShopifyTools.AuthController
      def auth(conn, _) do
        conn
        |> redirect(to: "/?token=" <> Guardian.Plug.current_token(conn))
      end

      @impl ShopifyTools.AuthController
      def on_install(conn, shop, _state) do
        client_id = ShopifyTools.Plug.fetch_client_id(conn)
        url = build_external_url(["https://", shop.url, "/admin/apps", client_id])
        redirect(conn, external: url)
      end

      def install(conn, %{"code" => code, "shop" => shop_url} = params) do
        state = Map.get(params, "state", "")
        shop_url = ShopifyTools.ShopValidator.validate_shop_url(shop_url)
        url = build_external_url(["https://", shop_url, "/admin/oauth/access_token"])

        req =
          Req.new(
            url: url,
            json: %{
              client_id: ShopifyTools.Plug.fetch_client_id(conn),
              client_secret: ShopifyTools.Plug.fetch_client_secret(conn),
              code: code
            },
            headers: [
              "Content-Type": "application/json",
              Accept: "application/json"
            ],
            decode_json: [keys: :atoms]
          )

        case Req.post(req) do
          {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
            shop = Map.put(body, :url, shop_url)
            # params = Map.put(params, ShopifyTool.Shops.get_scope_field(), params[:scope])

            # ShopifyTool.Shops.configure_webhooks(shop)

            on_install(conn, shop, state)

          {:ok, %Req.Response{status: status, body: body}} ->
            raise ShopifyTools.InstallError, message: "Installation failed for shop #{shop_url}"

          {:error, error} ->
            raise ShopifyTools.InstallError, message: "Installation failed for shop #{shop_url}"
        end
      end

      @impl ShopifyTools.AuthController
      def on_update(conn, shop, _state) do
        client_id = ShopifyTools.Plug.fetch_client_id(conn)
        url = build_external_url(["https://", shop.url, "/admin/apps", client_id])
        redirect(conn, external: url)
      end

      def update(conn, %{"code" => code, "shop" => shop_url} = params) do
        state = Map.get(params, "state", "")
        shop_url = ShopifyTools.ShopValidator.validate_shop_url(shop_url)
        url = build_external_url(["https://", shop_url, "/admin/oauth/access_token"])

        req =
          Req.new(
            url: url,
            json: %{
              client_id: ShopifyTools.Plug.fetch_client_id(conn),
              client_secret: ShopifyTools.Plug.fetch_client_secret(conn),
              code: code
            },
            headers: [
              "Content-Type": "application/json",
              Accept: "application/json"
            ],
            decode_json: [keys: :atoms]
          )

        case Req.post(req) do
          {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
            shop = Map.put(body, :url, shop_url)
            # params = Map.put(params, ShopifyTool.Shops.get_scope_field(), params[:scope])

            # ShopifyTool.Shops.configure_webhooks(shop)

            on_update(conn, shop, state)

          {:ok, %Req.Response{status: status, body: body}} ->
            raise ShopifyTools.UpdateError, message: "Update failed for shop #{shop_url}"

          error ->
            raise ShopifyTools.UpdateError, message: "Update failed for shop #{shop_url}"
        end
      end

      defoverridable on_install: 3, on_update: 3, auth: 2

      defp build_external_url(path, query_params \\ %{}) do
        Path.join(path) <> "?" <> URI.encode_query(query_params)
      end
    end
  end
end
