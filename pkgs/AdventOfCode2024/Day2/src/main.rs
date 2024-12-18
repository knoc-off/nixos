use std::fs::File;
use std::io::{BufRead, BufReader};


// example input data
// 7 6 4 2 1
// 1 2 7 8 9
// 9 7 6 2 1 2
// 1 3 2 4 5 5
// 8 6 4 4 1
// 1 3 6 7 9 4 3

struct report {
    levels: Vec<u32>,
}

fn parse_file(file: &str) -> Vec<report> {
    let mut reports = vec![];
    let f = File::open(file).expect("file not found");
    let reader = BufReader::new(f);
    for line in reader.lines() {
        let line = line.unwrap();
        let mut report = report { levels: vec![] };
        for word in line.split_whitespace() {
            let level = word.parse::<u32>().unwrap();
            report.levels.push(level);
        }
        reports.push(report);
    }
    reports
}


fn main() {

    let reports = parse_file("input.txt");

    // validate reports.
    // remove reports that have levels that differ by more than 3 and less than 1
    let mut valid_reports = vec![];
    for report in reports {
        let mut valid = true;
        let mut prev = 0;
        for level in report.levels {
            if level - prev > 3 || level - prev < 1 {
                valid = false;
                break;
            }
            prev = level;
        }
        if valid {
            valid_reports.push(report.clone());
        }
    }




    for report in valid_reports {
        println!("{:?}", report.levels);
    }
}

