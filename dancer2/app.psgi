#!/usr/bin/env perl

use strict;
use warnings;
use Plack::Builder;

use FindBin;
use lib $FindBin::Bin;
use Chat;

builder {
    mount( Chat->websocket_mount );
    mount '/' => Chat->to_app;
}
