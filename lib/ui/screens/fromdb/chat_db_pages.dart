import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_mqtt/abstraction/models/ChatMessage.dart';
import 'package:flutter_mqtt/abstraction/models/ContactChat.dart';
import 'package:flutter_mqtt/abstraction/models/enums/MessageType.dart';
import 'package:flutter_mqtt/db/appdata/AppData.dart';
import 'package:flutter_mqtt/db/database.dart';
import 'package:flutter_mqtt/global/ChatApp.dart';
import 'package:flutter_mqtt/ui/screens/fromdb/contact_page.dart';
import 'package:flutter_mqtt/ui/viewers/document_viewer.dart';
import 'package:flutter_mqtt/ui/viewers/media_viewer.dart';
import 'package:flutter_mqtt/ui/views/contact_avatar.dart';
import 'package:flutter_mqtt/ui/widgets/message_typing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:open_file/open_file.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_mqtt/ui/extensions/UiMessages.dart';

class ChatUIDBPage extends StatefulWidget {
  final ContactChat contactChat;
  const ChatUIDBPage({Key? key, required this.contactChat}) : super(key: key);

  @override
  _ChatUIPageState createState() => _ChatUIPageState();
}

class _ChatUIPageState extends State<ChatUIDBPage> {
  bool isTyping = false;
  final subscriptions = List<StreamSubscription<dynamic>>.empty(growable: true);
  types.User? _user;
  types.Message? respondToMessage;

  @override
  void initState() {
    AppData.instance()!
        .usersHandler
        .getLocalUser()
        .then((dbuser) => {_user = dbuser!.toUiUser2()});

    var s2 =
        ChatApp.instance()!.messageReader.getTypingMessages().listen((event) {
      if (event.roomId == widget.contactChat.roomId &&
          event.fromId != _user!.id) {
        setState(() {
          isTyping = event.isTyping;
        });
        Future.delayed(Duration(milliseconds: 3000), () {
          setState(() {
            isTyping = false;
          });
        });
      }
    });

    subscriptions.add(s2);
    super.initState();
  }

  void _handleAtachmentPressed() {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: SizedBox(
            height: 144,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _handleImageSelection();
                  },
                  child: const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Photo'),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _handleFileSelection();
                  },
                  child: const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('File'),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleFileSelection() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null) {
      String path = result.files.single.path;
      ChatApp.instance()!.messageSender.sendFileChatMessage(
          type: MessageType.ChatImage,
          fileLocalPath: path,
          room: widget.contactChat.roomId);
    }
  }

  void _handleImageSelection() async {
    final result = await ImagePicker().pickImage(
      imageQuality: 70,
      maxWidth: 1440,
      source: ImageSource.gallery,
    );

    if (result != null) {
      ChatApp.instance()!.messageSender.sendFileChatMessage(
          type: MessageType.ChatImage,
          fileLocalPath: result.path,
          room: widget.contactChat.roomId);
    }
  }

  void _handleMessageTap(types.Message message) async {
    //Handle PDF
    if (message is types.FileMessage && message.mimeType!.contains("pdf")) {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => DocumentViewer(
                  docUrl: message.uri,
                  title: message.name,
                )),
      );
    } else if (message is types.ImageMessage) {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => MediaViewerPage(
                  roomId: widget.contactChat.roomId,
                  messageId: message.id,
                )),
      );
    }
    //TODO: Handle DOC/DOCX/ODT/...
    //TODO: Handle TXT
  }

/*
  void _handlePreviewDataFetched(
    types.TextMessage message,
    types.PreviewData previewData,
  ) {
    final index = _messages.indexWhere((element) => element.id == message.id);
    final updatedMessage = _messages[index].copyWith(previewData: previewData);

    WidgetsBinding.instance?.addPostFrameCallback((_) {
      setState(() {
        _messages[index] = updatedMessage;
      });
    });
  }
*/
  void _handleSendPressed(types.PartialText message) {
    ChatMessage nm = ChatMessage(
        id: const Uuid().v4(),
        type: MessageType.ChatText,
        text: message.text,
        roomId: widget.contactChat.roomId,
        fromId: _user!.id,
        sendTime: DateTime.now().millisecondsSinceEpoch,
        fromName: _user!.firstName);
    if (respondToMessage == null) {
      ChatApp.instance()!
          .messageSender
          .sendChatMessage(nm, widget.contactChat.roomId);
    } else {
      final rep = ChatMessage(
          id: respondToMessage!.id,
          text: (respondToMessage! is types.TextMessage)
              ? (respondToMessage! as types.TextMessage).text
              : "File",
          type: MessageType.ChatText,
          sendTime: respondToMessage!.createdAt ?? 0,
          roomId: widget.contactChat.roomId);
      ChatApp.instance()!
          .messageSender
          .replyToMessage(rep, nm, widget.contactChat.roomId);
      setState(() {
        respondToMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          centerTitle: false,
          title: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        ContactDetailsPage(contactChat: widget.contactChat)),
              );
            },
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Hero(
                    tag: "avatar_" + widget.contactChat.id,
                    child: ContactAvatar(chat: widget.contactChat, radius: 15,),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.contactChat.firstName +
                        " " +
                        widget.contactChat.lastName),
                    Visibility(
                      child: Text(
                        "Typing...",
                        style: TextStyle(fontSize: 11),
                      ),
                      visible: isTyping,
                    )
                  ],
                ),
              ],
            ),
          )),
      body: StreamBuilder<List<DbMessage>>(
          stream: AppData.instance()!
              .messagesHandler
              .getMessagesByRoomId(widget.contactChat.roomId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(snapshot.error.toString());
            }
            if (snapshot.hasData) {
              var data = snapshot.data!.map((e) => e.toUiMessage()).toList();
              return Chat(
                messages: data,
                disableImageGallery: true,
                onAttachmentPressed: _handleAtachmentPressed,
                onMessageTap: _handleMessageTap,
                //onPreviewDataFetched: _handlePreviewDataFetched,
                onSendPressed: _handleSendPressed,
                onTextChanged: _handleTextChanged,
                onMessageLongPress: _handleLongPress,
                showUserNames: true,
                showUserAvatars: true,
                customBottomWidget: bottom(),
                user: _user!,
              );
            }
            return Text("Loading...");
          }),
    );
  }

  Widget bottom() {
    return MessageTyping(
        topWidget: respondToMessage != null
            ? respondToMessage!.toRespondedWidget(() => {
                  setState(() {
                    respondToMessage = null;
                  })
                })
            : null,
        onSendPressed: _handleSendPressed,
        onTextChanged: _handleTextChanged,
        onAttachmentPressed: _handleAtachmentPressed);
  }

  void _handleTextChanged(String text) {
    if (text.length > 0 && text.length % 3 == 0) {
      ChatApp.instance()!
          .eventsSender
          .sendIsTyping(true, widget.contactChat.roomId);
    }
  }

  @override
  void dispose() {
    subscriptions.forEach((element) {
      element.cancel();
    });
    super.dispose();
  }

  void _handleLongPress(types.Message message) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('Title'),
        message: const Text('Message'),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            child: const Text('Reply'),
            onPressed: () {
              setState(() {
                respondToMessage = message;
              });
              Navigator.pop(context);
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('Forward'),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('Delete'),
            onPressed: () {
              Navigator.pop(context);
            },
          )
        ],
      ),
    );
  }
}
