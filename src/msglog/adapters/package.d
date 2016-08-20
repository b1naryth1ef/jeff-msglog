module msglog.adapters;

public import msglog;
public import dscord.core;

struct MsgLogSearch {
  bool hasContents = false;
  bool hasCommand = false;

  Snowflake ignoreUser;

  string contents;
  bool command;
  Snowflake guild, channel, author;

  void setContents(string data) {
    this.hasContents = true;
    this.contents = data;
  }

  void setCommand(bool cmd) {
    this.hasCommand = true;
    this.command = cmd;
  }
}

struct MsgLogResult {
  Snowflake id, channel, author, guild;
  string timestamp, editedTimestamp, content;
  string authorName, channelName, guildName;
  bool command, deleted;
}

interface MsgLogAdapter {
  void load(MsgLogPlugin);
  void unload(MsgLogPlugin);

  // Evented handling of stuff
  void insertMessage(Message msg, bool isCommand);
  void updateMessage(Message msg);
  void deleteMessage(Snowflake id);

  // Searching
  MsgLogResult[] search(MsgLogSearch query);
}
