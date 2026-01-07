{
  lib,
  stdenvNoCC,
  python3,
  qrencode,
  fetchFromGitHub,
  domain ? "example.com",
  maxUserSendPerMinute ? 60,
  maxMailboxSize ? "500M",
  deleteMailsAfter ? "20",
  deleteInactiveUsersAfter ? 90,
  privacyMail ? "",
  privacyPostal ? "",
  privacyPdo ? "",
  privacySupervisor ? "",
  srcDir ? null,
  qrLogo ? null,
}:

let
  upstreamSrc = fetchFromGitHub {
    owner = "chatmail";
    repo = "relay";
    rev = "0e7ab96dc8fd8f6ac6d3a413c4fa0c0b21f2f9f5";
    hash = "sha256-thBFWMJqhsADY+AhODyWCoGQBHq5BA+5UD2TIrYnStc=";
  };

  templateSrc = if srcDir != null then srcDir else "${upstreamSrc}/www/src";

  useLogo = qrLogo != null;
  qrScript = ''
    import sys
    from io import BytesIO
    from pathlib import Path

    import qrcode
    from PIL import Image

    def gen_qr(domain, logo_path):
        url = f"DCACCOUNT:https://{domain}/new"

        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_H,
            box_size=1,
            border=1,
        )
        qr.add_data(url)
        qr.make(fit=True)
        qr_img = qr.make_image(fill_color="black", back_color="white")

        size = width = 384
        qr_padding = 6
        height = size

        image = Image.new("RGBA", (width, height), "white")
        qr_final_size = width - (qr_padding * 2)

        image.paste(
            qr_img.resize((qr_final_size, qr_final_size), resample=Image.NEAREST),
            (qr_padding, qr_padding),
        )

        # Add Delta Chat logo in center
        logo_img = Image.open(logo_path)
        logo_width = int(size / 6)
        logo = logo_img.resize((logo_width, logo_width), resample=Image.NEAREST)
        pos = int((size / 2) - (logo_width / 2))
        image.paste(logo, (pos, pos), mask=logo)

        return image

    if __name__ == "__main__":
        domain = sys.argv[1]
        output_path = sys.argv[2]
        logo_path = sys.argv[3]
        image = gen_qr(domain, logo_path)
        image.save(output_path, format="png")
  '';

  buildScript = ''
    import sys
    import re
    import markdown
    from pathlib import Path

    src_dir = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    mail_domain = sys.argv[3]

    config = {
        'mail_domain': mail_domain,
        'max_user_send_per_minute': '${toString maxUserSendPerMinute}',
        'max_mailbox_size': '${maxMailboxSize}',
        'delete_mails_after': '${deleteMailsAfter}',
        'delete_inactive_users_after': '${toString deleteInactiveUsersAfter}',
        'privacy_mail': '${privacyMail}',
        'privacy_postal': """${privacyPostal}""",
        'privacy_pdo': """${privacyPdo}""",
        'privacy_supervisor': """${privacySupervisor}""",
    }

    def process_jinja_conditionals(text, config):
        """Process Jinja2-style conditionals in text"""
        # Handle {% if config.mail_domain != "value" %}...{% else %}...{% endif %}
        # and {% if config.mail_domain == "value" %}...{% else %}...{% endif %}
        pattern = r'{%\s*if\s+config\.mail_domain\s*(==|!=)\s*["\']([^"\']+)["\']\s*%}(.*?)(?:{%\s*else\s*%}(.*?))?{%\s*endif\s*%}'

        def replace_conditional(match):
            op = match.group(1)
            compare_value = match.group(2)
            if_content = match.group(3) or ""
            else_content = match.group(4) or ""

            domain = config['mail_domain']
            if op == '==':
                return if_content if domain == compare_value else else_content
            else:  # !=
                return if_content if domain != compare_value else else_content

        return re.sub(pattern, replace_conditional, text, flags=re.DOTALL)

    layout_path = src_dir / 'page-layout.html'
    layout = layout_path.read_text()

    for md_file in src_dir.glob('*.md'):
        content = md_file.read_text()

        # Process Jinja2 conditionals first
        content = process_jinja_conditionals(content, config)

        for key, value in config.items():
            content = content.replace('{{ config.' + key + ' }}', str(value))
            content = content.replace('{{config.' + key + '}}', str(value))

        html_content = markdown.markdown(content)

        pagename = 'home' if md_file.stem == 'index' else md_file.stem

        page_html = layout
        page_html = page_html.replace('{{ markdown_html }}', html_content)
        page_html = page_html.replace('{{ pagename }}', pagename)

        # Process Jinja2 conditionals in layout
        page_html = process_jinja_conditionals(page_html, config)

        for key, value in config.items():
            page_html = page_html.replace('{{ config.' + key + ' }}', str(value))
            page_html = page_html.replace('{{config.' + key + '}}', str(value))

        # Remove webdev conditionals (development-only)
        page_html = re.sub(r'{%\s*if config\.webdev\s*%}.*?{%\s*endif\s*%}', "", page_html, flags=re.DOTALL)

        out_file = out_dir / (md_file.stem + '.html')
        out_file.write_text(page_html)

    for static_file in src_dir.iterdir():
        if static_file.suffix in ['.css', '.svg', '.png', '.txt', '.ico']:
            (out_dir / static_file.name).write_bytes(static_file.read_bytes())

    print(f'Built website for {mail_domain}')
  '';

in
stdenvNoCC.mkDerivation {
  pname = "chatmail-www";
  version = "1.0.0";

  src = templateSrc;

  nativeBuildInputs = [
    (python3.withPackages (
      ps:
      [ ps.markdown ]
      ++ lib.optionals useLogo [
        ps.qrcode
        ps.pillow
      ]
    ))
  ] ++ lib.optional (!useLogo) qrencode;

  dontConfigure = true;
  dontBuild = true;

  installPhase =
    let
      buildScriptFile = builtins.toFile "build-www.py" buildScript;
      qrScriptFile = builtins.toFile "gen-qr.py" qrScript;
    in
    ''
      runHook preInstall

      mkdir -p $out

      ${
        if useLogo then
          ''
            python3 ${qrScriptFile} "${domain}" "$out/qr-chatmail-invite-${domain}.png" "${qrLogo}"
          ''
        else
          ''
            qrencode -o $out/qr-chatmail-invite-${domain}.png -s 8 -l H \
              "DCACCOUNT:https://${domain}/new"
          ''
      }

      python3 ${buildScriptFile} "$src" "$out" "${domain}"

      runHook postInstall
    '';

  passthru = {
    defaultLogo = "${upstreamSrc}/cmdeploy/src/cmdeploy/data/delta-chat-bw.png";
  };

  meta = {
    description = "Chatmail static website for ${domain}";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
