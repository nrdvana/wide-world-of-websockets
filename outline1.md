## WebSocket

  * HTTP Request/response has latency weaknesses
  * WebSocket adds Peer-to-Peer messaging
  * TCP has always allowed this, but TCP+javascript can be abused
  * WebSocket builds on HTTP security principles
  * WebSocket also adds framing+reliability to messages
  * WebSocket was deployed in 2012, and now has near-ubiquitous support

## Websocket Examples

  * Chat
  * Real-time monitoring
  * Real-time Video Games
  * (joke) mining bitcoin
  * Jobs in queue
  * iPad Apps

## Websocket Motivation

  * Polling would be bad for any of those examples
  * Examples can be implemented with "Comet", but long requests cause loading
    animation for users, and users limited on number of requests they can
	open to same server.  Each HTTP request must be re-authenticated, and
    HTTP framing isn't very efficient for high-speed small messages.
  * Downside: requires persistent connection.

## WebSocket protocol

  * WebSocket starts as an HTTP request
  * Server responds a special way, and then both client and server know to immediately
    change the protocol used on that socket.
  * Early drafts of WebSocket required special handshake bytes to be sent;
    final draft is a pure HTTP request/response
  * Show request/response
  * Websocket wire protocol is "slim".
  * Show example of packets.  Point out most details unimportant, but note the
    overall efficiency of byte count.

## WebSockets In Perl

  * Now you know what a websocket is and why you would use it.
  * Goal of this talk is to show all the ways to do websockets in Perl
    and discuss pros/cons.
  * However, many of the challenges involved with WebSockets are the more
    general challenges involved with Event Driven Programming and concurrency,
	so I'm going to review those topics first, to make sure everyone on same page
	and using the same terminology.

## Event-Driven Programming

  * The most basic type of program is one that runs one algorithm to calculate
    an output from an input.
  * You know all steps the program might take in advance, and write the code for
    that sequence of steps.  If you need data that isn't immediately available,
	you "block" the program until it is and then continue the sequence of steps.
  * The other main kind of program is one whose progessing depends on external events.
    The program has no goal aside from responding to events with various behavior.
  * A web server is a form of event-driven program that we're all familiar with.
  * The web server waits for client requests, then runs the request to completion and
    sends a response.
  * Each perl web framework is an exampe of some manner of tackling the problem of
    how to link an incoming event to the relevant code.

## Concurrency

  * Most of the time, you want an event-driven program to be able to respond to
    multiple events at once, so that short events don't have to wait for longer
	events to finish.  Or, just for capacity.
  * Three main strategies are:
    * Multiple independent processes which each process one event at a time
	  (usually coordinated via filesystem or database)
	* Multiple threads where each thread processes one event at a time
	  (coordinated via shared data and synchronization "objects")
	* Single thread written in non-blocking style
  * Pro/Con matrix of each mechanism
  * Perl doesn't get option 2, because no threads.  (But I don't really want it anyway,
    because multithread synchronization is a mess.)
  * Frameworks like Plack, Catalyst and Dancer use option 1, though you can get option 3
    if you try hard enough.
  * Frameworks like Mojo lend themselves naturally to option 3, though not required.

## Non-blocking Concurrency in Perl

  * Probably a lot of perl programmers who haven't done non-blocking code before
  * Example of plain-old-select-loop in perl
  * List of libraries that do non-blocking
     * POE
	 * AnyEvent
	 * IO::Async
  * 

## Standalone WebSocket Server

  POE?
  AnyEvent::WebSocket::Server
  IO::Async?

## Plack

  * PSGI Specification doesn't officially support WebSocket
  * Plack provides WebSocket, implemented in a way that works with Twiggy
  * I have also implemented by just never invoking responder

## Catalyst

  * No support.  Can be made to work with some private method calls.

## Dancer

  * Fake support.  Dancer cannot respond to incoming websocket requests or websocket messages.

## Mojolicious

  * Full support.  Mojo was designed specifically for non-blocking style apps.
  * Mojo provides own event loop implementation/API
  * Mojo has specific integration for passing events through postgres

## CGI

  * Might seem silly, but could work for some use cases
  * Do whatever makes sense for the problem you are solving.

## Why Make Monoliths?

  * Use Traefik or other frontend to divide application according to need.  Put normal
    web requests in Catalyst/Dancer, and websocket related code in Mojo or standalone
  * Can use Postgres event system to bridge them together.
  * Or, just make microservices, which could even run on separate hosts.

## Summary

  * Prime-time for websockets has arrived
  * Lots of options.  Easy to get started.
  * Bigger learning curve is just getting familiar with non-blocking programming.
  * Links to modules, technologies, and slides.

