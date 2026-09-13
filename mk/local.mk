# mk/local.mk: the consumer hook of this repository (MK-LOCAL).
# sync never touches this file.

# The executable joins the module and shebang scan
PERL_SRC_DIRS	= lib bin scripts

# The full test tier set of make test
TEST_GLOBS	= t/fugubench/*.t t/ci/*.t
