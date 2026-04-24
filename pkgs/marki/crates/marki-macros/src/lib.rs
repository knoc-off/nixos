//! `#[derive(ParseTag)]` — a small DSL for turning `#keyword` / `#keyword(args)`
//! tokens in markdown into enum variants.
//!
//! The generated code references `crate::tag::TagParseError`, so the crate
//! invoking the derive must provide that type (see `marki-core::tag`).

use proc_macro::TokenStream;
use quote::quote;
use syn::{Data, DeriveInput, Fields, GenericArgument, Lit, Meta, PathArguments, Type, parse_macro_input};

#[proc_macro_derive(ParseTag, attributes(tag))]
pub fn derive_parse_tag(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    let name = &input.ident;

    let Data::Enum(data_enum) = &input.data else {
        return syn::Error::new_spanned(&input.ident, "ParseTag can only be derived for enums")
            .to_compile_error()
            .into();
    };

    let mut match_arms = Vec::new();

    for variant in &data_enum.variants {
        let explicit_tag = variant.attrs.iter().find_map(|attr| {
            if attr.path().is_ident("tag") {
                if let Meta::List(meta_list) = &attr.meta {
                    if let Ok(Lit::Str(lit_str)) = syn::parse2(meta_list.tokens.clone()) {
                        return Some(lit_str.value());
                    }
                }
            }
            None
        });

        let variant_ident = &variant.ident;
        let keyword = explicit_tag.unwrap_or_else(|| variant_ident.to_string().to_lowercase());

        let arm = match &variant.fields {
            Fields::Unit => {
                quote! {
                    #keyword => {
                        if args.is_some() {
                            return ::core::result::Result::Err(
                                crate::tag::TagParseError::UnexpectedArg(#keyword.to_string())
                            );
                        }
                        ::core::result::Result::Ok(Self::#variant_ident)
                    }
                }
            }
            Fields::Unnamed(fields) if fields.unnamed.len() == 1 => {
                let field = fields.unnamed.first().unwrap();
                let ty = &field.ty;

                if let Some(inner) = option_inner_type(ty) {
                    quote! {
                        #keyword => {
                            match args {
                                ::core::option::Option::None => {
                                    ::core::result::Result::Ok(Self::#variant_ident(::core::option::Option::None))
                                }
                                ::core::option::Option::Some(arg) => {
                                    let parsed: #inner = arg.parse().map_err(|_| {
                                        crate::tag::TagParseError::BadArg {
                                            tag: #keyword.to_string(),
                                            arg: arg.to_string(),
                                        }
                                    })?;
                                    ::core::result::Result::Ok(Self::#variant_ident(::core::option::Option::Some(parsed)))
                                }
                            }
                        }
                    }
                } else {
                    quote! {
                        #keyword => {
                            let arg = args.ok_or_else(|| crate::tag::TagParseError::MissingArg(#keyword.to_string()))?;
                            let parsed: #ty = arg.parse().map_err(|_| {
                                crate::tag::TagParseError::BadArg {
                                    tag: #keyword.to_string(),
                                    arg: arg.to_string(),
                                }
                            })?;
                            ::core::result::Result::Ok(Self::#variant_ident(parsed))
                        }
                    }
                }
            }
            _ => {
                return syn::Error::new_spanned(
                    variant,
                    "ParseTag: only unit variants and single-field tuple variants are supported",
                )
                .to_compile_error()
                .into();
            }
        };

        match_arms.push(arm);
    }

    let expanded = quote! {
        impl ::core::str::FromStr for #name {
            type Err = crate::tag::TagParseError;

            fn from_str(s: &str) -> ::core::result::Result<Self, Self::Err> {
                let s = s.trim();
                let s = s.strip_prefix('#').unwrap_or(s);
                let (keyword, args): (&str, ::core::option::Option<&str>) =
                    match s.find('(') {
                        ::core::option::Option::Some(open) => {
                            if !s.ends_with(')') {
                                return ::core::result::Result::Err(
                                    crate::tag::TagParseError::Malformed(s.to_string())
                                );
                            }
                            let kw = &s[..open];
                            let inner = &s[open + 1..s.len() - 1];
                            (kw, ::core::option::Option::Some(inner))
                        }
                        ::core::option::Option::None => (s, ::core::option::Option::None),
                    };

                match keyword {
                    #(#match_arms)*
                    other => ::core::result::Result::Err(
                        crate::tag::TagParseError::Unknown(other.to_string())
                    ),
                }
            }
        }
    };

    TokenStream::from(expanded)
}

/// Detect `Option<T>` and return `T`.
fn option_inner_type(ty: &Type) -> Option<&Type> {
    let Type::Path(type_path) = ty else { return None };
    let last = type_path.path.segments.last()?;
    if last.ident != "Option" {
        return None;
    }
    let PathArguments::AngleBracketed(args) = &last.arguments else { return None };
    for arg in &args.args {
        if let GenericArgument::Type(t) = arg {
            return Some(t);
        }
    }
    None
}
