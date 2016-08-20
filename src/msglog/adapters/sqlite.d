module msglog.adapters.sqlite;

import d2sqlite3;
import d2sqlite3 : sqlite3Config = config;

import std.array,
       std.format,
       std.path;

import msglog.adapters;

class SqliteAdapter : MsgLogAdapter {
  Database db;

  void optimize() {
    this.db.run(`INSERT INTO messages_fts(messages_fts) VALUES('optimize');`);
  }

  void load(MsgLogPlugin plugin) {
    sqlite3Config(SQLITE_CONFIG_MULTITHREAD);

    this.db = Database(plugin.storageDirectoryPath ~ dirSeparator ~ "messages.db");
    this.createTable();
    this.db.run(format(`PRAGMA busy_timeout = %s;`, plugin.config.get!ushort("busy_timeout", 500)));
  }

  void unload(MsgLogPlugin plugin) {
    this.db.close();
  }

  void createTable() {
    this.db.run(`
      CREATE TABLE IF NOT EXISTS messages (
        id UNSIGNED BIG INT PRIMARY KEY,
        channel UNSIGNED BIG INT,
        author UNSIGNED BIG INT,
        guild UNSIGNED BIG INT,
        timestamp DATETIME,
        edited_timestamp DATETIME,
        content TEXT,
        author_name VARCHAR(256),
        channel_name VARCHAR(256),
        guild_name VARCHAR(256),
        command BOOLEAN,
        deleted BOOLEAN
      );`);

    this.db.run(`
      CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts4(
        content, author, channel, guild
    );`);
  }

  void insertMessage(Message msg, bool isCommand) {
    Statement stmt = db.prepare(`
      INSERT INTO messages
        (id, channel, author, guild, timestamp, content,
          author_name, channel_name, guild_name, command)
      VALUES
        (:id, :channel, :author, :guild, :timestamp, :content,
          :author_name, :channel_name, :guild_name, :command);
    `);

    stmt.bind(":id", msg.id);
    stmt.bind(":channel", msg.channel.id);
    stmt.bind(":author", msg.author.id);
    stmt.bind(":guild", msg.guild ? msg.guild.id : 0);
    stmt.bind(":timestamp", msg.timestamp);
    stmt.bind(":content", msg.content);
    stmt.bind(":author_name", msg.author.username);
    stmt.bind(":channel_name", msg.channel.name);
    stmt.bind(":guild_name", msg.guild ? msg.guild.name : null);
    stmt.bind(":command", isCommand);
    stmt.execute();

    stmt = db.prepare(`
      INSERT INTO messages_fts
        (docid, content, author, channel, guild)
      VALUES
        (:id, :content, :author_name, :channel_name, :guild_name);
    `);
    stmt.bind(":id", msg.id);
    stmt.bind(":content", msg.content);
    stmt.bind(":author_name", msg.author.username);
    stmt.bind(":channel_name", msg.channel.name);
    stmt.bind(":guild_name", msg.guild ? msg.guild.name : null);
    stmt.execute();
  }

  void updateMessage(Message msg) {
    Statement stmt = db.prepare(`
      UPDATE messages SET
        content = :content,
        edited_timestamp = :edited_ts
      WHERE (id = :id);
    `);

    stmt.bind(":id", msg.id);
    stmt.bind(":content", msg.content);
    stmt.bind(":edited_ts", msg.editedTimestamp);
    stmt.execute();

    stmt = db.prepare(`
      UPDATE messages_fts SET
        content = :content
      WHERE (docid = :id)
    `);
    stmt.bind(":id", msg.id);
    stmt.bind(":content", msg.content);
    stmt.execute();
  }

  void deleteMessage(Snowflake id) {
    db.prepare("UPDATE messages SET deleted = 1 WHERE id = :id").inject(id);
  }

  MsgLogResult[] search(MsgLogSearch query) {
    MsgLogResult[] results;

    string queryString = `
      SELECT docid, b.*
      FROM messages_fts a
      JOIN messages b ON (a.docid = b.id)
      WHERE
    `;

    string[] parts;

    if (query.hasContents) parts ~= "a.content MATCH :contents";
    if (query.hasCommand) parts ~= "b.command = :command";
    if (query.guild) parts ~= "b.guild = :guild";
    if (query.channel) parts ~= "b.channel = :channel";
    if (query.author) parts ~= "b.author = :author";
    if (query.ignoreUser) parts ~= "NOT b.author = :ignore_user";

    queryString ~= parts.join("\n AND ");
    queryString ~= "\n ORDER BY b.timestamp DESC;";

    Statement stmt = db.prepare(queryString);
    if (query.hasContents) stmt.bind(":contents", query.contents);
    if (query.hasCommand) stmt.bind(":command", query.command);
    if (query.guild) stmt.bind(":guild", query.guild);
    if (query.channel) stmt.bind(":channel", query.channel);
    if (query.author) stmt.bind(":author", query.author);
    if (query.ignoreUser) stmt.bind(":ignore_user", query.ignoreUser);

    auto rows = stmt.execute();

    foreach (row; rows) {
      results ~= MsgLogResult(
        row["id"].as!Snowflake,
        row["channel"].as!Snowflake,
        row["author"].as!Snowflake,
        row["guild"].as!Snowflake,
        row["timestamp"].as!string,
        row["edited_timestamp"].as!string,
        row["content"].as!string,
        row["author_name"].as!string,
        row["channel_name"].as!string,
        row["guild_name"].as!string,
        row["command"].as!bool,
        row["deleted"].as!bool,
      );
    }

    return results;
  }
}
