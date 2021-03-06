type result =
  | Accepted
  | Unknown_exception of exn
  | Authentication_failure of X509.Validation.validation_error

let pp_leaf_validation_error ppf = function
  | `LeafCertificateExpired _ -> Format.fprintf ppf "expired"
  | `LeafInvalidName _ -> Format.fprintf ppf "invalid name"
  | `LeafInvalidVersion _ -> Format.fprintf ppf "invalid version"
  | `LeafInvalidExtensions _ -> Format.fprintf ppf "invalid extensions"

let pp_result ppf = function
  | Accepted -> Format.pp_print_string ppf "Accepted"
  | Unknown_exception e ->
      Format.fprintf ppf "Unknown_exception: %s" (Printexc.to_string e)
  | Authentication_failure (`Leaf e) ->
      Format.fprintf ppf "Authentication failure (leaf: %a)"
        pp_leaf_validation_error e
  | Authentication_failure e ->
      Format.fprintf ppf "Authentication failure: %a"
        X509.Validation.pp_validation_error e

let to_authenticator_param = function
  | Some x -> x
  | None ->
      print_endline "defaulting to null auth";
      `No_authentication_I'M_STUPID

let make_client () =
  let open Lwt in
  Ca_certs.detect () >>= fun r ->
  to_authenticator_param r |> X509_lwt.authenticator >|= fun authenticator ->
  Tls.Config.client ~authenticator ()

let connect client host =
  let open Lwt in
  let create () = Tls_lwt.Unix.connect client (host, 443) in
  let act tls = Tls_lwt.Unix.close tls >|= fun () -> Accepted in
  let on_exn = function
    | Tls_lwt.Tls_failure (`Error (`AuthenticationFailure f)) ->
        return (Authentication_failure f)
    | e -> return (Unknown_exception e)
  in
  Lwt.try_bind create act on_exn

let test client host =
  let open Lwt in
  connect client host >|= fun result ->
  Format.printf "%s -> %a\n" host pp_result result

let main () =
  let open Lwt in
  make_client () >>= fun client ->
  Lwt_list.iter_s (test client)
    [
      "google.com";
      "self-signed.badssl.com";
      "expired.badssl.com";
      "untrusted-root.badssl.com";
      "revoked.badssl.com";
      "extended-validation.badssl.com";
    ]

let () = Lwt_main.run (main ())
