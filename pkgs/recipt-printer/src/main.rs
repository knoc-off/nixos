use clap::Parser;
use escpos::printer::Printer;
use escpos::printer_options::PrinterOptions;
use escpos::utils::*;
use escpos::{driver::*, errors::Result};
use std::io::{self, IsTerminal, Read};

mod markdown;

#[derive(Parser, Debug)]
#[command(about = "Print to thermal receipt printer")]
struct Args {
    /// Text to print (reads from stdin if not provided)
    text: Option<String>,

    #[arg(long)]
    markdown: bool,

    #[arg(long)]
    cut: bool,

    /// Print test page for font size calibration
    #[arg(long)]
    test_page: bool,

    /// Print an image from file path
    #[arg(long)]
    image: Option<String>,

    /// Image width in pixels (default: 384, max depends on printer)
    #[arg(long, default_value = "384")]
    image_width: u32,
}

fn print_test_page<D>(printer: &mut Printer<D>) -> Result<()>
where
    D: escpos::driver::Driver,
{
    printer.init()?.writeln("=== Font Size Test Page ===")?;
    printer.feed()?;

    // Test 1x1 (normal) - test widths 38-48
    printer.size(1, 1)?;
    for w in 38..=48 {
        let left = "1x1 ";
        printer.writeln(&format!("{}{:>width$}", left, w, width = w - left.len()))?;
    }
    printer.size(1, 1)?;
    printer.feed()?;

    // Test 2x1 (wide) - test widths 18-25
    printer.size(2, 1)?;
    for w in 18..=25 {
        let left = "2x1 ";
        printer.writeln(&format!("{}{:>width$}", left, w, width = w - left.len()))?;
    }
    printer.size(1, 1)?;
    printer.feed()?;

    // Test 1x2 (tall) - test widths 38-48
    printer.size(1, 2)?;
    for w in 38..=48 {
        let left = "1x2 ";
        printer.writeln(&format!("{}{:>width$}", left, w, width = w - left.len()))?;
    }
    printer.size(1, 1)?;
    printer.feed()?;

    // Test 2x2 (double size) - test widths 18-25
    printer.size(2, 2)?;
    for w in 18..=25 {
        let left = "2x2 ";
        printer.writeln(&format!("{}{:>width$}", left, w, width = w - left.len()))?;
    }
    printer.size(1, 1)?;
    printer.feed()?;

    // Test Font B (smaller) - test widths 50-62
    printer.font(Font::B)?;
    for w in 50..=62 {
        let left = "FontB ";
        printer.writeln(&format!("{}{:>width$}", left, w, width = w - left.len()))?;
    }
    printer.font(Font::A)?;
    printer.feed()?;

    printer.print_cut()?;
    Ok(())
}

fn find_thermal_printer() -> Option<(u16, u16)> {
    // Known thermal printer vendor IDs
    let known_vendors = [
        0x04b8, // Epson
        0x0519, // Star
        0x1d90, // Citizen
        0x0dd4, // Seiko
        0x1504, // Bixolon
        0x0525, // Netchip Technology (used in examples)
    ];

    if let Ok(devices) = rusb::devices() {
        for device in devices.iter() {
            if let Ok(desc) = device.device_descriptor() {
                let vendor_id = desc.vendor_id();
                let product_id = desc.product_id();

                // Check if it's a known thermal printer vendor
                if known_vendors.contains(&vendor_id) {
                    return Some((vendor_id, product_id));
                }
            }
        }
    }
    None
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Search for printer
    let (vendor_id, product_id) = if let Some((vid, pid)) = find_thermal_printer() {
        println!("Found thermal printer: {:04x}:{:04x}", vid, pid);
        (vid, pid)
    } else {
        eprintln!("Error: No thermal printer detected.");
        std::process::exit(1);
    };

    let driver =
        UsbDriver::open(vendor_id, product_id, None, None).expect("Failed to open USB printer");

    let mut printer = Printer::new(driver, Protocol::default(), Some(PrinterOptions::default()));

    printer
        .debug_mode(Some(DebugMode::Dec))
        .init()?
        .smoothing(true)?
        .line_spacing(1)?;

    if args.test_page {
        return print_test_page(&mut printer);
    }

    if let Some(image_path) = args.image {
        printer.bit_image_option(
            &image_path,
            BitImageOption::new(Some(args.image_width), None, BitImageSize::Normal)?,
        )?;
        printer.feed()?.print()?;

        if args.cut {
            printer.cut()?.print()?;
        }

        return Ok(());
    }

    let text = if let Some(t) = args.text {
        t
    } else {
        if io::stdin().is_terminal() {
            std::process::exit(1);
        }

        let mut buffer = String::new();
        io::stdin()
            .read_to_string(&mut buffer)
            .expect("Failed to read from stdin");
        buffer
    };

    if args.markdown {
        markdown::print_markdown(&mut printer, &text)?;
        printer.feed()?.print()?;
    } else {
        printer.init()?.writeln(&text)?.feed()?.print()?;
    }

    if args.cut {
        printer.cut()?.print()?;
    }

    Ok(())
}
