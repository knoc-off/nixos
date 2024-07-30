use crate::data::link::ImageLinkData;


#[derive(Clone, PartialEq)]
pub struct ContactInfo {
    pub email: String,
    pub phone: String,
    pub location: String,
    pub social_links: Vec<ImageLinkData>,
}
