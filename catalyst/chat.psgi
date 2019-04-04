use strict;
use warnings;

use Chat;

my $app = Chat->apply_default_middlewares(Chat->psgi_app);
$app;

