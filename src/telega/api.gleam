import gleam/http/request.{type Request}
import gleam/http/response.{type Response, Response}
import gleam/http.{Get, Post}
import gleam/option.{type Option, None, Some}
import gleam/json
import gleam/httpc
import gleam/result
import gleam/dynamic.{type DecodeError, type Dynamic}
import telega.{type Bot, type Context}
import telega/model.{
  type BotCommand, type BotCommandParameters, type Message,
  type SendDiceParameters, type User,
}

const telegram_url = "https://api.telegram.org/bot"

type TelegramApiRequest {
  TelegramApiPostRequest(
    url: String,
    body: String,
    query: Option(List(#(String, String))),
  )
  TelegramApiGetRequest(url: String, query: Option(List(#(String, String))))
}

type ApiResponse(result) {
  ApiResponse(ok: Bool, result: result)
}

// TODO: Support all options from the official reference.
/// Set the webhook URL using [setWebhook](https://core.telegram.org/bots/api#setwebhook) API.
/// **Official reference:** https://core.telegram.org/bots/api#setwebhook
pub fn set_webhook(bot: Bot) -> Result(Bool, String) {
  let webhook_url = bot.config.server_url <> "/" <> bot.config.webhook_path
  let query = [
    #("url", webhook_url),
    #("secret_token", bot.config.secret_token),
  ]

  new_get_request(
    token: bot.config.token,
    path: "setWebhook",
    query: Some(query),
  )
  |> fetch
  |> map_resonse(dynamic.bool)
}

// TODO: Support all options from the official reference.
/// Use this method to send text messages.
/// **Official reference:** https://core.telegram.org/bots/api#sendmessage
pub fn reply(ctx ctx: Context, text text: String) -> Result(Message, String) {
  new_post_request(
    token: ctx.bot.config.token,
    path: "sendMessage",
    body: json.object([
        #("chat_id", json.int(ctx.message.raw.chat.id)),
        #("text", json.string(text)),
      ])
      |> json.to_string,
    query: None,
  )
  |> fetch
  |> map_resonse(model.decode_message)
}

/// Use this method to change the list of the bot's commands. See [commands documentation](https://core.telegram.org/bots/features#commands) for more details about bot commands. Returns True on success.
/// **Official reference:** https://core.telegram.org/bots/api#setmycommands
pub fn set_my_commands(
  ctx ctx: Context,
  commands commands: List(BotCommand),
  parameters parameters: Option(BotCommandParameters),
) -> Result(Bool, String) {
  let parameters =
    option.unwrap(parameters, model.new_botcommand_parameters())
    |> model.encode_botcommand_parameters

  let body_json =
    json.object([
      #(
        "commands",
        json.array(commands, fn(command: BotCommand) {
          json.object([
            #("command", json.string(command.command)),
            #("description", json.string(command.description)),
            ..parameters
          ])
        }),
      ),
    ])

  new_post_request(
    token: ctx.bot.config.token,
    path: "setMyCommands",
    body: json.to_string(body_json),
    query: None,
  )
  |> fetch
  |> map_resonse(dynamic.bool)
}

/// Use this method to delete the list of the bot's commands for the given scope and user language. After deletion, [higher level commands](https://core.telegram.org/bots/api#determining-list-of-commands) will be shown to affected users.
/// **Official reference:** https://core.telegram.org/bots/api#deletemycommands
pub fn delete_my_commands(
  ctx: Context,
  parameters parameters: Option(BotCommandParameters),
) -> Result(Bool, String) {
  let parameters =
    option.unwrap(parameters, model.new_botcommand_parameters())
    |> model.encode_botcommand_parameters

  let body_json = json.object(parameters)

  new_post_request(
    token: ctx.bot.config.token,
    path: "deleteMyCommands",
    body: json.to_string(body_json),
    query: None,
  )
  |> fetch
  |> map_resonse(dynamic.bool)
}

/// Use this method to get the current list of the bot's commands for the given scope and user language.
/// **Official reference:** https://core.telegram.org/bots/api#getmycommands
pub fn get_my_commands(
  ctx: Context,
  parameters parameters: Option(BotCommandParameters),
) -> Result(List(BotCommand), String) {
  let parameters =
    option.unwrap(parameters, model.new_botcommand_parameters())
    |> model.encode_botcommand_parameters

  let body_json = json.object(parameters)

  new_post_request(
    token: ctx.bot.config.token,
    path: "getMyCommands",
    query: None,
    body: json.to_string(body_json),
  )
  |> fetch
  |> map_resonse(model.decode_bot_command)
}

/// Use this method to send an animated emoji that will display a random value.
/// **Official reference:** https://core.telegram.org/bots/api#senddice
pub fn send_dice(
  ctx: Context,
  parameters parameters: Option(SendDiceParameters),
) -> Result(Message, String) {
  let parameters =
    option.unwrap(
      parameters,
      model.new_send_dice_parameters(ctx.message.raw.chat.id),
    )
  let body_json = model.encode_send_dice_parameters(parameters)

  new_post_request(
    token: ctx.bot.config.token,
    path: "sendDice",
    query: None,
    body: json.to_string(body_json),
  )
  |> fetch
  |> map_resonse(model.decode_message)
}

/// A simple method for testing your bot's authentication token.
/// **Official reference:** https://core.telegram.org/bots/api#getme
pub fn get_me(ctx: Context) -> Result(User, String) {
  new_get_request(token: ctx.bot.config.token, path: "getMe", query: None)
  |> fetch
  |> map_resonse(model.decode_user)
}

fn new_post_request(
  token token: String,
  path path: String,
  body body: String,
  query query: Option(List(#(String, String))),
) {
  let url = telegram_url <> token <> "/" <> path

  TelegramApiPostRequest(url: url, body: body, query: query)
}

fn new_get_request(
  token token: String,
  path path: String,
  query query: Option(List(#(String, String))),
) {
  let url = telegram_url <> token <> "/" <> path

  TelegramApiGetRequest(url: url, query: query)
}

fn set_query(
  api_request: Request(String),
  query: Option(List(#(String, String))),
) -> Request(String) {
  case query {
    None -> api_request
    Some(query) -> {
      request.set_query(api_request, query)
    }
  }
}

fn api_to_request(
  api_request: TelegramApiRequest,
) -> Result(Request(String), String) {
  case api_request {
    TelegramApiGetRequest(url: url, query: query) -> {
      request.to(url)
      |> result.map(request.set_method(_, Get))
      |> result.map(set_query(_, query))
    }
    TelegramApiPostRequest(url: url, query: query, body: body) -> {
      request.to(url)
      |> result.map(request.set_body(_, body))
      |> result.map(request.set_method(_, Post))
      |> result.map(request.set_header(_, "Content-Type", "application/json"))
      |> result.map(set_query(_, query))
    }
  }
  |> result.map_error(fn(_) { "Failed to convert API request to HTTP request" })
}

fn fetch(api_request: TelegramApiRequest) {
  use api_request <- result.try(api_to_request(api_request))

  httpc.send(api_request)
  |> result.map_error(fn(error) {
    dynamic.string(error)
    |> result.unwrap("Failed to send request")
  })
}

fn map_resonse(
  response: Result(Response(String), String),
  result_decoder: fn(Dynamic) -> Result(a, List(DecodeError)),
) -> Result(a, String) {
  response
  |> result.map(fn(response) {
    let Response(body: body, ..) = response
    let decode = response_decoder(result_decoder)
    json.decode(body, decode)
    |> result.map_error(fn(_) { "Failed to decode response: " <> body })
    |> result.map(fn(response) { response.result })
  })
  |> result.flatten
}

fn response_decoder(result_decoder: fn(Dynamic) -> Result(a, List(DecodeError))) {
  dynamic.decode2(
    ApiResponse,
    dynamic.field("ok", dynamic.bool),
    dynamic.field("result", result_decoder),
  )
}
