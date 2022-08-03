module Google.Apis.Drive.v3.DriveMyNullable;

import std.typecons: Nullable, nullable;
import std.conv: to;

struct MyNullable(T) {
  Nullable!T val;
  alias val this;

  static MyNullable!T fromString(string value) @safe {
    return MyNullable!T((to!T(value)).nullable);
  }

  string toString() const @safe {
    return val.isNull ? "" : to!string(val.get);
  }
}
