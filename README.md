# privateparlor

A rewrite of [secretlounge-ng](https://github.com/secretlounge/secretlounge-ng), a bot to make an anonymous group chat on Telegram. 
Written in Crystal with the aim of being a fast, memory efficient, and featureful alternative.

[Updates posted on Telegram](https://t.me/privateparlor)
## Installation

~~~
git clone https://gitlab.com/Charibdys/privateparlor.git
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
leave - alias of stop
~~~

## Usage

1. Rename `config.yaml.copy` to `config.yaml`
2. Edit config file, it should at least have the API token for your bot and a path to a SQLite database
3. Run the binary found in `bin/`

## Development

The following features are planned and being worked on:

- [ ] Relay message types
	- [x] Text
	- [x] Photos
	- [X] Albums
	- [x] Videos
	- [x] Files/Documents
	- [x] GIFs
	- [x] Stickers
	- [x] Polls
	- [ ] Venues/Contacts
	- [x] Forwards
- [ ] Admin commands
	- [ ] Configurable command permissions 
- [ ] Message history
	- [ ] Configurable cache contents
	- [x] Configurable cache life
- [ ] Karma
- [x] Message queue
- [ ] Spam prevention
	- [ ] Configurable time and content limits
- [ ] Inactivity timeout
- [ ] CLI tools and utility scripts

## Contributing

This project has a [Trello board](https://trello.com/b/6W5ZX7BD/private-parlor-development) which you can use to see open tasks and progress.

If you would like to make a contribution, follow these steps:

1. Fork it (<https://gitlab.com/Charibdys/private-parlor/-/forks/new>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

Ensure that your code is documented and follows the [Crystal API coding style](https://crystal-lang.org/reference/1.2/conventions/coding_style.html).

## Contributors

- [Charybdis](https://gitlab.com/Charibdys) - creator and maintainer
