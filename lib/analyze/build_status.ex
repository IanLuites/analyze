defmodule Analyze.BuildStatus do
  @moduledoc false

  @options [
    :with_body,
    ssl_options: [versions: [:"tlsv1.2"]],
    pool: :default
  ]

  def report(key, state, label, description \\ "") do
    headers =
      [
        {"Content-Type", "application/x-www-form-urlencoded"}
      ] ++ repo_status_authorization()

    body =
      %{
        "state" => state,
        "key" => "MIX-ANALYZE-" <> key,
        "name" => label,
        "url" => Application.get_env(:analyze, :status_build_url),
        "description" => description
      }
      |> URI.encode_query()

    :hackney.request(:POST, repo_status_url(), headers, body, @options)
  end

  defp repo_status_authorization do
    case Application.get_env(:analyze, :status_authorization) do
      nil -> repo_status_oauth()
      auth -> [{"Authorization", "Basic " <> auth}]
    end
  end

  defp repo_status_oauth do
    case Application.get_env(:analyze, :status_refresh_token) do
      nil ->
        []

      {id, token} ->
        headers = [
          {"Content-Type", "application/x-www-form-urlencoded"},
          {"Authorization", "Basic " <> Base.encode64(id)}
        ]

        body =
          %{
            grant_type: "refresh_token",
            refresh_token: token
          }
          |> URI.encode_query()

        case :hackney.request(
               :POST,
               "https://bitbucket.org/site/oauth2/access_token",
               headers,
               body,
               @options
             ) do
          {:ok, 200, _, auth_json} ->
            auth = Jason.decode!(auth_json)

            [{"Authorization", "Bearer " <> auth["access_token"]}]

          5 ->
            []
        end
    end
  end

  defp repo_status_url do
    case Application.get_env(:analyze, :status_endpoint) do
      nil ->
        nil

      url ->
        url
        |> String.split(~r/\${(.*?)}/, include_captures: true)
        |> Enum.map(&replace_env_vars/1)
        |> Enum.join()
    end
  end

  defp replace_env_vars(value) do
    cond do
      !String.starts_with?(value, "${") ->
        value

      !String.ends_with?(value, "}") ->
        value

      true ->
        value
        |> String.trim_leading("${")
        |> String.trim_trailing("}")
        |> System.get_env()
    end
  end
end
