module msglog;

import std.format,
       std.path,
       std.array,
       std.conv;

import jeff.perms;
import msglog.adapters,
       msglog.adapters.sqlite;
import dscord.core,
       dscord.util.emitter;

class MsgLogPlugin : Plugin {
  // Database instance
  MsgLogAdapter adapter;

  this() {
    auto opts = new PluginOptions;
    opts.useStorage = true;
    opts.useConfig = true;
    super(opts);
  }

  override void load(Bot bot, PluginState state = null) {
    super.load(bot, state);
    this.adapter = new SqliteAdapter();
    this.adapter.load(this);
  }

  override void unload(Bot bot) {
    this.adapter.unload(this);
    super.unload(bot);
  }

  @Command("global")
  @CommandDescription("search message logs globally")
  @CommandGroup("search")
  @CommandLevel(Level.ADMIN)
  void onSearchCommandGlobal(CommandEvent event) {
    MsgLogSearch query;
    query.ignoreUser = this.bot.client.me.id;
    query.setContents(event.cleanedContents);
    query.setCommand(false);

    auto results = this.adapter.search(query);
    event.msg.reply(this.formatResults(results));
  }

  MessageBuffer formatResults(MsgLogResult[] results) {
    MessageBuffer msg = new MessageBuffer;

    if (!results.length) {
      msg.appendf("No results found");
      return msg;
    }

    foreach (result; results) {
      if (!msg.appendf("[%s] (%s / %s) %s: %s",
            result.timestamp,
            result.guildName,
            result.channelName,
            result.authorName,
            result.content)) break;
    }

    return msg;
  }

  @Command("channel")
  @CommandDescription("search message logs in this channel")
  @CommandGroup("search")
  @CommandLevel(Level.MOD)
  void onSearchChannelCommand(CommandEvent event) {
    MsgLogSearch query;
    query.ignoreUser = this.bot.client.me.id;
    query.setContents(event.cleanedContents);
    query.setCommand(false);
    query.channel = event.msg.channel.id;

    auto results = this.adapter.search(query);
    event.msg.reply(this.formatResults(results));
  }

  @Command("guild")
  @CommandDescription("search message logs in this guild")
  @CommandGroup("search")
  @CommandLevel(Level.ADMIN)
  void onSearchGuildCommand(CommandEvent event) {
    if (!event.msg.guild) {
      return;
    }

    MsgLogSearch query;
    query.ignoreUser = this.bot.client.me.id;
    query.setContents(event.cleanedContents);
    query.setCommand(false);
    query.guild = event.msg.guild.id;

    auto results = this.adapter.search(query);
    event.msg.reply(this.formatResults(results));
  }

  @Command("user")
  @CommandDescription("search message logs by user")
  @CommandGroup("search")
  @CommandLevel(Level.ADMIN)
  void onSearchUser(CommandEvent event) {
    if (event.args.length < 1 && event.msg.mentions.length != 2) {
      event.msg.replyf("Must provide user to search by");
      return;
    }

    MsgLogSearch query;

    if (event.msg.mentions.length == 2) {
      query.author = event.msg.mentions.values[1].id;
      query.setContents(event.cleanedContents);
    } else {
      query.author = event.args[0].to!Snowflake;
      if (event.args.length > 1) {
        query.setContents(event.args[1..$].join(" "));
      }
    }

    query.ignoreUser = this.bot.client.me.id;
    query.setCommand(false);

    auto results = this.adapter.search(query);
    event.msg.reply(this.formatResults(results));
  }

  @Listener!MessageCreate(EmitterOrder.AFTER)
  void onMessageCreate(MessageCreate event) {
    this.adapter.insertMessage(event.message, event.commandEvent !is null);
  }

  @Listener!MessageUpdate(EmitterOrder.AFTER)
  void onMessageUpdate(MessageUpdate event) {
    this.adapter.updateMessage(event.message);
  }

  @Listener!MessageDelete(EmitterOrder.AFTER)
  void onMessageDelete(MessageDelete event) {
    this.adapter.deleteMessage(event.id);
  }
}

extern (C) Plugin create() {
  return new MsgLogPlugin;
}
