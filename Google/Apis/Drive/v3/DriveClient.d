module Google.Apis.Drive.v3.DriveClient;


import std.file : read, readText, write, exists;
import cerealed;
import requests;
import std.stdio;
import std.json;
import std.conv : to;
import std.array : replace, split;
import std.datetime.systime;
import core.time : seconds;
import std.format : format;
import vibe.data.json;
import Google.Apis.Drive.v3.DriveScopes: Scopes, DriveScopes;
import std.exception: enforce;

class DriveClient {
    /* Google APIs code uri */
    private static const string API_CODE_URI = "https://accounts.google.com/o/oauth2/v2/auth";

    /* Google APIs token uri */
    private static const string API_TOKEN_URI = "https://oauth2.googleapis.com/token";

    /* Name of the file that stores the access token */
    private static const string ACCESS_TOKEN_FILE = "DriveAccessToken";

    /* Name of the file that stores the refresh token */
    private static const string REFRESH_TOKEN_FILE = "DriveRefreshToken";

    private Creds _creds;
    private string _scope;
    private string _clientCode;
    private string _redirectUri;

    this(string credentialsFile, Scopes _scope) {
        string credsJsonString;

        enforce(credentialsFile.exists, "Credentials file does not exist.");

        credsJsonString = readText(credentialsFile);
        this._creds = deserializeJson!Creds(credsJsonString);
        this._scope = DriveScopes.all()[_scope];
        this._redirectUri = _creds.web.redirect_uris[0];

        if (!ACCESS_TOKEN_FILE.exists) {
            authorize();
        }
    }

    public string getScope() {
        return this._scope;
    }

    public DriveClient setScope(Scopes _scope) {
        this._scope = DriveScopes.all()[_scope];
        authorize();
        return this;
    }

    private string getCode(ushort port) {
        import std.socket : TcpSocket, Socket, InternetAddress;

        string code = "";
        Socket reads = null;
        auto listener = new TcpSocket();
        enforce(listener.isAlive);

        listener.bind(new InternetAddress(port));
        listener.listen(10);

        reads = listener.accept();
        enforce(reads.isAlive);
        enforce(listener.isAlive);

        char[1024] buf;
        auto dataLength = reads.receive(buf[]);

        if (dataLength == Socket.ERROR) {
            writeln("Connection error.");
            stdout.flush();
                    return "";
        }
        else if (dataLength != 0)
        {
            code ~= buf[0 .. dataLength];
        }
        reads.close();
        listener.close();
        code = code.split("?")[1].split("&")[0].split("=")[1];

        return code;
    }

    AccessToken authorize(RequestT = Request, ResponseT = Response)() {
        import core.stdc.stdlib: getenv;
        auto browserEnvVariable = getenv("BROWSER");
        if (browserEnvVariable !is null) {
            const string browserEnvVariableString = to!(string)(browserEnvVariable);
            auto command = [browserEnvVariableString, this.getCodeString];
            import std.process: spawnProcess;
            
            spawnProcess(command);
        } else {
            writeln("To authorize the client, please use this link " ~
                this.getCodeString ~ " and authorize it.");	
        }

        import std.string: indexOf, lastIndexOf;
        
        enforce(_redirectUri.indexOf(":") != _redirectUri.lastIndexOf(":"), "No port found in the redirect uri");
        
        ushort port = to!(ushort)(this._redirectUri.split(":")[2].split("/")[0]);
        this._clientCode = this.getCode(port);
        enforce(this._clientCode != "", "Could not retrieve the authentication_code.");

        static if (is(RequestT == Request)) {
            RequestT request = Request();
            request.sslSetVerifyPeer(false);

            ResponseT response = request.post(getAuthorizeString, []);
            JSONValue responseBody = parseJSON(response.responseBody.toString);

            AccessToken accessToken =
                AccessToken(responseBody["access_token"].str, Clock.currTime, responseBody["expires_in"].get!long);
            write(ACCESS_TOKEN_FILE, accessToken.serializeToJson().toString);
            write(REFRESH_TOKEN_FILE, cerealise(cast(ubyte[])responseBody["refresh_token"].str));

            return accessToken;
        } else {
            writefln("%s not supported.", RequestT.stringof);
            return AccessToken();
        }
    }

    AccessToken refreshToken(RequestT = Request, ResponseT = Response)() {
        if (!REFRESH_TOKEN_FILE.exists) {
            return authorize();
        }

        string refreshToken = decerealise!string(
            cast(ubyte[])read(REFRESH_TOKEN_FILE)
        ).replace("\\", "");

        static if(is(RequestT == Request)) {
            RequestT request = Request();
            request.sslSetVerifyPeer(false);

            ResponseT response =
                request.post(getRefreshTokenString(refreshToken), []);
            JSONValue responseBody = parseJSON(response.responseBody.toString);

            AccessToken accessToken = AccessToken(responseBody["access_token"].str,
                                                  Clock.currTime,
                                                  responseBody["expires_in"].get!long);
            write(ACCESS_TOKEN_FILE, accessToken.serializeToJson().toString);
            
            return accessToken;
        } else {
            writefln("%s not supported.", RequestT.stringof);
            return AccessToken();
        }
    }

    public string getToken() {
        if (!ACCESS_TOKEN_FILE.exists) {
            return authorize()._accessToken;
        }

        AccessToken accessToken = deserializeJson!AccessToken(
            to!(string)(read(ACCESS_TOKEN_FILE))
        );

        if (accessToken.isExpired) {
            accessToken = this.refreshToken();
        }

        return accessToken._accessToken;
    }

    private string getCodeString() {
        const string fmt = "%s?scope=%s&redirect_uri=%s&client_id=%s&" ~
                           "access_type=offline&response_type=code&" ~
                           "include_granted_scopes=true&prompt=consent";
        return format!fmt(API_CODE_URI, _scope, _redirectUri, _creds.web.client_id);
    }

    private string getAuthorizeString() {
        const string fmt = "%s?code=%s&client_id=%s&client_secret=%s&" ~
                           "redirect_uri=%s&grant_type=authorization_code";
        return format!fmt(API_TOKEN_URI, _clientCode, _creds.web.client_id,
                          _creds.web.client_secret, _redirectUri);
    }

    private string getRefreshTokenString(string refreshToken) {
        const string fmt = "%s?client_id=%s&client_secret=%s&" ~
                           "refresh_token=%s&grant_type=refresh_token";
        return format!fmt(API_TOKEN_URI, _creds.web.client_id,
                          _creds.web.client_secret, refreshToken);
    }
    
    private static struct AccessToken {
        string _accessToken;
        SysTime _authorizedTime;
        long _availability;
        
        bool isExpired() {
            return Clock.currTime >= (_authorizedTime + _availability.seconds);
        }
    }

    static class Web {
        string client_id;
        string project_id;
        string auth_uri;
        string token_uri;
        string auth_provider_x509_cert_url;
        string client_secret;
        string[] redirect_uris;
    }

    static class Creds {
        Web web;
    }
}
