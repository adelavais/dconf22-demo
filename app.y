/* Adela VAIS
   Dconf 2022
 */

%language "D"

%define api.parser.class {FileManagerDemo}
%define parse.error detailed
%define api.push-pull push
%define api.token.constructor
%define api.value.type union

%locations

/* Bison Declarations */
%token LOGIN    "autentifică"
       LOGOUT   "deconectează"
       CREATE   "creează"
       DELETE   "șterge"
       WRITE    "scrie"
       IN       "în"
       APPEND   "adaugă"
       EOL      "final de rând"

%token <string> PARAM "parametru"

%printer { yyo.write($$); } <string>

/* Grammar follows */
%%
input:
  line
| input line
;

line:
  EOL
| exp EOL           { }
| error EOL         { yyerrok(); }
;

exp:
  LOGIN PARAM PARAM                   { loginFile($2, $3);  }
| LOGOUT PARAM                        { logoutFile($2);     }
| CREATE PARAM                        { createFile($2);     }
| DELETE PARAM                        { deleteFile($2);     }
| WRITE IN PARAM PARAM                { writeFile($3, $4);  }
| APPEND IN PARAM PARAM               { appendFile($3, $4); }
;

%%
import std.range.primitives;
import std.stdio;

import Google.Apis.Drive.v3.DriveClient: DriveClient;
import Google.Apis.Drive.v3.Drive;
import Google.Apis.Drive.v3.Data.About: About;
import Google.Apis.Drive.v3.DriveScopes: Scopes, DriveScopes;

string fileId;

void loginFile(string user, string pass)
{
    assert(user in credentials , "Credențiale incorecte. Încercați din nou.");
    writeln("Autentificare reușită pentru utilizatorul ", user, ".");
}

void logoutFile(string user)
{
    writeln("Deconectare reușită pentru utilizatorul ", user, ".");
}

void appendFile(string name, string contents)
{
    import requests;
    import Google.Apis.Drive.v3.Data.File: File;
    File f = _drive.files()
                .get_!(Request, Response)(fileId)
                .execute();
    f._id = "";
    fileContent ~= "\n" ~ contents;

    import core.time;
    import core.thread.osthread;
    Thread.sleep(dur!("seconds")(7));

    //upload the file to google drive
    auto res = _drive.files()
                .update_!(Request, Response, string)(fileId, f, fileContent)
                .upload();

    writeln("Fișierul ", name, " a fost suprascris și are conținutul: \"", fileContent, "\".");
}

void writeFile(string name, string contents)
{
    import requests;
    import Google.Apis.Drive.v3.Data.File: File;
    File f = _drive.files()
                .get_!(Request, Response)(fileId)
                .execute();
    f._id = "";

    import core.time;
    import core.thread.osthread;
    Thread.sleep(dur!("seconds")(5));

    fileContent = contents;

    //upload the file to google drive
    auto res = _drive.files()
                .update_!(Request, Response, string)(fileId, f, fileContent)
                .upload();

    writeln("Fișierul ", name, " a fost suprascris și are conținutul: \"", fileContent, "\".");
}

void createFile(string name)
{
    import Google.Apis.Drive.v3.Data.File: File;
    File f = File().setName(name);

    import std.stdio: File;
    import std.file;
    std.file.write(name, " ");
    auto content = std.stdio.File(name);

    import requests;
    auto res = _drive.files()
                .create_!(Request, Response, std.stdio.File)(f, content)
                .upload();
    writeln("Fișierul ", name, " a fost creat.");

    fileId = res._id;
}

void deleteFile(string name)
{
    import core.time;
    import core.thread.osthread;
    Thread.sleep(dur!("seconds")( 5 ));

    import requests;
    auto res = _drive.files()
                .delete_!(Request, Response)(fileId).execute();

    writeln("Fișierul ", name, " a fost șters.");
}

void getCredentials()
{
  credentials["adela"] = "adela";
  credentials["edi"] = "edi";
  credentials["robert"] = "robert";
  assert(credentials["adela"] == "adela");
  assert(!("adi" in credentials));
}

string fileContent = "";

auto calcLexer(R)(R range)
if (isInputRange!R && is(ElementType!R : dchar))
{
  return new CalcLexer!R(range);
}

Drive _drive;
enum string CREDENTIALS_FILE = "secret.json";
string[string] credentials;

auto calcLexer(File f)
{
  import std.algorithm : map, joiner;
  import std.utf : byDchar;

  return f.byChunk(1024)        // avoid making a syscall roundtrip per char
          .map!(chunk => cast(char[]) chunk) // because byChunk returns ubyte[]
          .joiner               // combine chunks into a single virtual range of char
          .calcLexer;           // forward to other overload
}

class CalcLexer(R) : Lexer
if (isInputRange!R && is(ElementType!R : dchar))
{
  R input;

  this(R r) { input = r; }

  Location location;

  bool userOp = false;

  // Should be a local in main, shared with %parse-param.
  int exit_status = 0;

  void yyerror(const Location loc, string s)
  {
    exit_status = 1;
    stderr.writeln(loc.toString(), ": ", s);
  }

  Symbol yylex()
  {
    import std.uni : isWhite, isNumber;

    // Skip initial spaces
    while (!input.empty && input.front != '\n' && isWhite(input.front))
    {
      location.end.column++;
      input.popFront;
    }
    location.step();

    if (input.empty)
      return Symbol.YYEOF(location);

    import std.array;
    import std.conv;

    dchar[] w;
    w.length = 0;

    while (!isWhite(input.front))
    {
        ++w.length;
        w[$-1] = input.front;
        input.popFront;
        location.end.column++;
    }

    if (w.length == 0 && input.front == '\n')
    {
      ++w.length;
      w[$-1] = input.front;
      input.popFront;
      location.end.column++;
    }

    switch (w[])
    {
      case "autentifică":   return Symbol.LOGIN(location);
      case "deconectează":  return Symbol.LOGOUT(location);
      case "creează":       return Symbol.CREATE(location);
      case "șterge":        return Symbol.DELETE(location);
      case "scrie":         return Symbol.WRITE(location);
      case "în":            return Symbol.IN(location);
      case "adaugă":        return Symbol.APPEND(location);
      case "\n":
      {
        location.end.line++;
        location.end.column = 1;
        return Symbol.EOL(location);
      }
      default: return Symbol.PARAM(to!string(w[]), location);
    }
  }
}

int main()
{
  getCredentials();
  _drive = new Drive(CREDENTIALS_FILE, Scopes.DRIVE);

  File f = File("input");
  auto l = calcLexer(f);
  auto p = new FileManagerDemo(l);
  int status;
  do {
    status = p.pushParse(l.yylex());
  } while (status == PUSH_MORE);
  return l.exit_status;
}
