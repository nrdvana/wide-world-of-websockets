Wide World of Websockets
------------------------

## What is a Websocket

  * Starts as an HTTP request
  * Converts TCP connection to a peer-to-peer protocol
  * Messages are framed, not pure streams

## Why Websockets

  * Some problems are solved best with event-based design
  * HTTP awkward for exchanging events

### Example: Chat

  * Want to deliver messages from server to client ASAP

### Example: Watching Status

  * Want to avoid lots of polling

### Example: iPad Apps

  * Want responsive UI via web

## Event Driven Programming

  * Blocking vs. Nonblocking
  * Event Loops
  * Event libraries
  * What about blocking Libraries
  * Single Thread

## In Unix

  * File Handles
  * Signals
  * Timers
  * Can use libraries as long as they expose FH

## In Windows

  * Threads and IPC
  * Pipe Problems

## Event-Driven with Perl

  * Can't use blocking libs
  * Probably ned a special DB access

### AnyEvent

  * Wraps other event libs with clean API
  * Lots of callbacks, beware memory leaks
  * See mailing list for past drama

### Mojo

  * Standalone event system

### POE

  * Slightly awkward but old and stable API

### Others

## Websocket Design Considerations vs. MVC

  * MVC worker pool is useful
  * Lose that when establishing long-lived connections
  * Can reconnect automatically with Javascript

## Websockets in Apps

### Standalone Websocket Server

  * Simplest example
  * SSL awkward, need extra port configured
  * Workarounds, will come back to this
  * Nice connection object

### Mojo

  * Ecosystem designed for event-driven, makes websockets easy
  * (TODO: more research)

### Plack

  * Awkward callback system allows for websockets
  * Requires special support from server
  * Connection details tangled in closures

### Web::Simple

  * Mostly same as Plack

### Catalyst

  * Catalyst uses Plack callback responder
  * Hold onto $c
  * Example

### Dancer

  * Also Plack, and can use responder
  * Dancer uses lots of globals, so event-driven requires special API
  * Dancer is pretty, event-driven Dancer not so much

### Web::ConServe

  * One object per request, app object becomes connection object
  * Less closure mess

### CGI

  * Each request is own process
  * Can use blocking calls

### Forking from the App

  * Careful handoff of filehandles can work

## Deployment

  * Need to consider worker pool

### Docker

  * probably set each continer to be worker pool

### Nginx

  * Cn reverse-proxy to standalone websocket server!

### Traefik

  * Better reverse proxy
  * Ties into docker better
