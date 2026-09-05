import * as philips from 'zigbee-herdsman-converters/lib/philips';

export default {
    zigbeeModel: ['LTA016'],
    model: 'LTA016',
    vendor: 'Signify Netherlands B.V.',
    description: 'Hue White Ambiance',
    extend: [philips.m.light({colorTemp: {range: [50, 1000]}})],
};
