requires 'Object::Pad', '>= 0.808';
requires 'Class::Method::Modifiers', 0;
requires 'curry', 0;
requires 'Future', '>= 0.40';
requires 'Future::AsyncAwait', '>= 0.33';
requires 'indirect', 0;
requires 'IO::Async', '>= 0.68';
requires 'IO::Async::Notifier', '>= 0.68';
requires 'JSON::MaybeUTF8', 0;
requires 'List::Util', '>= 1.50';
requires 'List::UtilsBy', 0;
requires 'Log::Any', '>= 1.050';
requires 'Module::Load', 0;
requires 'mro', 0;
requires 'parent', 0;
requires 'Path::Tiny', '>= 0.108';
requires 'perl', '5.024';
requires 'Ryu', '>= 3.002';
requires 'Ryu::Async', '>= 0.016';
requires 'Scalar::Util', '>= 1.50';
requires 'Syntax::Keyword::Try', '>= 0.11';
requires 'Template', '>= 3.000';
requires 'URI', 0;
requires 'URI::db', '>= 0.19';
requires 'YAML::XS', 0;

on 'test' => sub {
    requires 'Test::More', '>= 0.98';
    requires 'Test::Fatal', '>= 0.010';
    requires 'Test::Refcount', '>= 0.07';
    requires 'Test::CheckDeps', 0;
};

on 'develop' => sub {
    requires 'Test::CPANfile', '>= 0.02';
    requires 'Devel::Cover::Report::Coveralls', '>= 0.11';
    requires 'Devel::Cover';
};
