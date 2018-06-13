to assert v1 v2 message {
  if (isNil message) { message = '' }
  if (v1 == v2) {
     print 'ok'
     return true
  } else {
     print message v2 'expected, but got' v1
     return false
  }
}

to assertNotEqual v1 v2 message {
  if (isNil message) { message = '' }
  if (not (v1 == v2)) {
     print 'ok'
     return true
  } else {
     print message v2 'not expected'
     return false
  }
}
