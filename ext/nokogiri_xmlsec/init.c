#include "xmlsecrb.h"
#include "util.h"

#include <xmlsec/dl.h>
#include <xmlsec/errors.h>

#ifndef XMLSEC_NO_XSLT
#include <libxslt/xslt.h>
#include <libxslt/security.h>
#endif /* XMLSEC_NO_XSLT */

static void init_xmlsec() {
#ifndef XMLSEC_NO_XSLT
    xsltSecurityPrefsPtr xsltSecPrefs = NULL;
#endif /* XMLSEC_NO_XSLT */

  /* xmlsec proper */
  // libxml
  xmlInitParser();
  LIBXML_TEST_VERSION
  xmlLoadExtDtdDefaultValue = XML_DETECT_IDS | XML_COMPLETE_ATTRS;
  // xslt

#ifndef XMLSEC_NO_XSLT
  xmlIndentTreeOutput = 1;

  /* Disable all XSLT options that give filesystem and network access. */
  xsltSecPrefs = xsltNewSecurityPrefs();
  xsltSetSecurityPrefs(xsltSecPrefs,  XSLT_SECPREF_READ_FILE,        xsltSecurityForbid);
  xsltSetSecurityPrefs(xsltSecPrefs,  XSLT_SECPREF_WRITE_FILE,       xsltSecurityForbid);
  xsltSetSecurityPrefs(xsltSecPrefs,  XSLT_SECPREF_CREATE_DIRECTORY, xsltSecurityForbid);
  xsltSetSecurityPrefs(xsltSecPrefs,  XSLT_SECPREF_READ_NETWORK,     xsltSecurityForbid);
  xsltSetSecurityPrefs(xsltSecPrefs,  XSLT_SECPREF_WRITE_NETWORK,    xsltSecurityForbid);
  xsltSetDefaultSecurityPrefs(xsltSecPrefs);
#endif /* XMLSEC_NO_XSLT */

  // xmlsec

  if (xmlSecInit() < 0) {
    rb_raise(rb_eRuntimeError, "xmlsec initialization failed");
    return;
  }
  if (xmlSecCheckVersion() != 1) {
    rb_raise(rb_eRuntimeError, "xmlsec version is not compatible");
    return;
  }
  // load crypto
  #ifdef XMLSEC_CRYPTO_DYNAMIC_LOADING
    if(xmlSecCryptoDLLoadLibrary(NULL) < 0) {
      rb_raise(rb_eRuntimeError,
        "Error: unable to load default xmlsec-crypto library. Make sure"
        "that you have it installed and check shared libraries path\n"
        "(LD_LIBRARY_PATH) envornment variable.\n");
      return;
    }
  #endif /* XMLSEC_CRYPTO_DYNAMIC_LOADING */
  // init crypto
  if (xmlSecCryptoAppInit(NULL) < 0) {
    rb_raise(rb_eRuntimeError, "unable to initialize crypto engine");
    return;
  }
  // init xmlsec-crypto library
  if (xmlSecCryptoInit() < 0) {
    rb_raise(rb_eRuntimeError, "xmlsec-crypto initialization failed");
  }
}

VALUE rb_cNokogiri_XML_Document = Qnil;
VALUE rb_cNokogiri_XML_Node = Qnil;
VALUE rb_eSigningError = Qnil;
VALUE rb_eVerificationError = Qnil;
VALUE rb_eKeystoreError = Qnil;
VALUE rb_eEncryptionError = Qnil;
VALUE rb_eDecryptionError = Qnil;

EXTENSION_EXPORT
void Init_nokogiri_xmlsec() {
  init_xmlsec();
  VALUE XMLSec = rb_define_module("XMLSec");
  VALUE Nokogiri = rb_define_module("Nokogiri");
  VALUE Nokogiri_XML = rb_define_module_under(Nokogiri, "XML");
  rb_cNokogiri_XML_Document = rb_const_get(Nokogiri_XML, rb_intern("Document"));
  rb_cNokogiri_XML_Node = rb_const_get(Nokogiri_XML, rb_intern("Node"));

  rb_define_method(rb_cNokogiri_XML_Node,     "sign!",            sign, 1);
  rb_define_method(rb_cNokogiri_XML_Node,     "verify_with",      verify_with, 1);
  rb_define_method(rb_cNokogiri_XML_Node,     "encrypt_with_key", encrypt_with_key, 3);
  rb_define_method(rb_cNokogiri_XML_Node,     "decrypt_with_key", decrypt_with_key, 2);
  rb_define_method(rb_cNokogiri_XML_Document, "get_id",           get_id, 1);
  rb_define_method(rb_cNokogiri_XML_Node,     "set_id_attribute", set_id_attribute, 1);

  rb_eSigningError      = rb_define_class_under(XMLSec, "SigningError",      rb_eRuntimeError);
  rb_eVerificationError = rb_define_class_under(XMLSec, "VerificationError", rb_eRuntimeError);
  rb_eKeystoreError     = rb_define_class_under(XMLSec, "KeystoreError",     rb_eRuntimeError);
  rb_eEncryptionError   = rb_define_class_under(XMLSec, "EncryptionError",   rb_eRuntimeError);
  rb_eDecryptionError   = rb_define_class_under(XMLSec, "DecryptionError",   rb_eRuntimeError);
}

