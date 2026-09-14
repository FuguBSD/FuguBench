# mk/local.mk: the consumer hook of this repository (MK-LOCAL).
# sync never touches this file.

# The executable joins the module and shebang scan
PERL_SRC_DIRS	= lib bin scripts

# make dist builds the packed file as well as the tarball
# (DIST-PACK-1). scripts/pack runs scripts/dist first, with the same
# values, and it packs the tarball that the build writes
# (DIST-PACK-7).
DIST		= scripts/pack

# The full test tier set of make test
TEST_GLOBS	= t/fugubench/*.t t/ci/*.t
