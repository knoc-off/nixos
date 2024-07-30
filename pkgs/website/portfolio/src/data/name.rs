// data/name.rs
#[derive(Clone, PartialEq)]
pub struct Name {
    pub first: String,
    pub middle: Option<String>,
    pub last: String,
}

impl Name {
    pub fn full_name(&self) -> String {
        match &self.middle {
            Some(middle) => format!("{} {} {}", self.first, middle, self.last),
            None => format!("{} {}", self.first, self.last),
        }
    }
}
