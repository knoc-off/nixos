use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, Data, DeriveInput, Fields, Lit, Meta};

#[proc_macro_derive(ParseTag, attributes(tag, default))]
pub fn derive_parse_tag(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    let name = &input.ident;

    let Data::Enum(data_enum) = &input.data else {
        panic!("ParseTag can only be derived for enums");
    };

    let mut match_arms = Vec::new();
    let mut generic_variant = None;

    for variant in &data_enum.variants {
        // Look for #[tag("name")] attribute
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

        let variant_name = &variant.ident;

        // Default to lowercase variant name if no explicit tag
        let tag_name = explicit_tag.unwrap_or_else(|| variant_name.to_string().to_lowercase());

        match tag_name.as_str() {
            "*" => {
                // Catch-all variant
                generic_variant = Some(quote! {
                    _ => Self::#variant_name(s.to_string())
                });
            }
            tag => {
                // Named tag variant
                match &variant.fields {
                    Fields::Unit => {
                        // No fields, just match the tag
                        match_arms.push(quote! {
                            #tag => Self::#variant_name
                        });
                    }
                    Fields::Named(fields) => {
                        // Struct variant with fields
                        let field_inits: Vec<_> = fields
                            .named
                            .iter()
                            .map(|f| {
                                let field_name = f.ident.as_ref().unwrap();
                                let field_type = &f.ty;

                                // Check for #[default(...)] attribute
                                let has_default =
                                    f.attrs.iter().any(|attr| attr.path().is_ident("default"));

                                if has_default {
                                    quote! {
                                        #field_name: parts.next()
                                            .and_then(|s| s.parse::<#field_type>().ok())
                                            .unwrap_or_default()
                                    }
                                } else {
                                    quote! {
                                        #field_name: parts.next()
                                            .and_then(|s| s.parse::<#field_type>().ok())
                                            .unwrap_or_default()
                                    }
                                }
                            })
                            .collect();

                        match_arms.push(quote! {
                            #tag => {
                                Self::#variant_name {
                                    #(#field_inits),*
                                }
                            }
                        });
                    }
                    Fields::Unnamed(_) => {
                        panic!("Tuple variants not yet supported");
                    }
                }
            }
        }
    }

    let generic_arm = generic_variant.unwrap_or_else(|| {
        quote! {
            _ => panic!("Unknown tag: {}", s)
        }
    });

    let expanded = quote! {
        impl #name {
            pub fn parse(s: &str) -> Self {
                let s = s.trim_start_matches('#');
                let mut parts = s.split(':');
                let keyword = parts.next().unwrap_or("");

                match keyword {
                    #(#match_arms,)*
                    #generic_arm
                }
            }
        }
    };

    TokenStream::from(expanded)
}
