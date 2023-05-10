# privateparlor

A rewrite of [secretlounge-ng](https://github.com/secretlounge/secretlounge-ng), a bot to make an anonymous group chat on Telegram. 
Written in Crystal with the aim of being a fast, memory efficient, and featureful alternative.

Using the [Tourmaline](https://github.com/protoncr/tourmaline) Telegram bot library.

[Updates posted on Telegram](https://t.me/privateparlor)
## Installation

Compiling PrivateParlor requires having both `crystal` and `shards` installed.

~~~
git clone https://github.com/Charibdys/Private-Parlor.git
cd privateparlor
shards install
shards build --release
~~~

## BotFather Setup
1. Start a conversation with [BotFather](https://t.me/botfather)
2. Make a new bot with `/newbot` and answer the prompts
3. `/setprivacy`: enabled
4. `/setjoingroups`: disabled
5. `/setcommands`: paste the following command list here

### Command list

~~~
start - Join the chat (start receiving messages)
stop - Leave the chat (stop receiving messages)
leave - Alias of stop
info - Get info about your account
users - Show the number of users in the chat
version - Get the version and a link to the source code
togglekarma - Toggle karma notifications
toggledebug - Toggle debug mode (sends messages back to you)
tripcode - Set or view your tripcode
rules - Show the rules of this chat
sign - Sign a message with your username
tsign - Sign a message with your tripcode
s - Alias of sign
t - Alias of tsign
~~~

Commands can also be registered with BotFather in the config file. These commands will overwrite the command list above.

## Usage

1. Rename `config.yaml.copy` to `config.yaml`
2. Edit config file, it should at least have the API token for your bot and a path to a SQLite database
3. Run the binary found in `bin/`

## Development

The following features are planned and being worked on:

- [x] Relay message types
	- [x] Text
	- [x] Photos
	- [X] Albums
	- [x] Videos
	- [x] Files/Documents
	- [x] GIFs
	- [x] Stickers
	- [x] Polls
	- [x] Locations/Venues
	- [x] Contacts
	- [x] Forwards
- [x] Admin commands
	- [X] Delete
	- [X] Delete all
	- [X] Remove
	- [X] Warn
	- [X] Uncooldown
	- [X] Setting rules/MOTD
	- [X] User info
	- [X] Blacklist
	- [X] Promotion 
	- [X] Demotion 
- [x] Message history/cache
- [X] Karma
	- [X] Upvotes
	- [X] Downvotes
- [x] Message queue
- [x] Spam prevention
- [X] Configuration
	- [X] Configurable roles and command permissions 
	- [X] Configurable cache contents/data
	- [x] Configurable cache life
	- [x] Configurable time and content limits for spam filter
- [ ] Inactivity timeout
- [ ] CLI tools and utility scripts

## Contributing

Open tasks and current planned features can be found in this repo's project, [Private Parlor Development](https://github.com/users/Charibdys/projects/1)

If you would like to make a contribution, follow these steps:

1. Fork it (<https://github.com/Charibdys/Private-Parlor/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

Ensure that your code is documented and follows the [Crystal API coding style](https://crystal-lang.org/reference/1.6/conventions/coding_style.html).

## Contributors

- [Charybdis](https://gitlab.com/Charibdys) - creator and maintainer
