
use std/assert

use ../nu/common.nu [compare-ver]

#[test]
def 'v1.0.0 is greater than v0.1.0' [] {
  assert equal (compare-ver 1.0.0 0.1.0) 1
  assert equal (compare-ver v1.0.0 v0.1.0) 1
}

#[test]
def 'v1.0.1 is equal to v1.0.1' [] {
  assert equal (compare-ver 1.0.1 1.0.1) 0
}

#[test]
def 'v1.0.1 is lower than v1.1.0' [] {
  assert equal (compare-ver 1.0.1 1.1.0) (-1)
}
