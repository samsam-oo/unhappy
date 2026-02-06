import * as React from 'react';
import {
    View,
    Text,
    StyleProp,
    ViewStyle,
    TextStyle,
    Platform
} from 'react-native';
import { Typography } from '@/constants/Typography';
import { layout } from './layout';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';

interface ItemChildProps {
    showDivider?: boolean;
    [key: string]: any;
}

export interface ItemGroupProps {
    title?: string | React.ReactNode;
    footer?: string;
    children: React.ReactNode;
    style?: StyleProp<ViewStyle>;
    headerStyle?: StyleProp<ViewStyle>;
    footerStyle?: StyleProp<ViewStyle>;
    titleStyle?: StyleProp<TextStyle>;
    footerTextStyle?: StyleProp<TextStyle>;
    containerStyle?: StyleProp<ViewStyle>;
}

const stylesheet = StyleSheet.create((theme, runtime) => ({
    wrapper: {
        alignItems: 'center',
    },
    container: {
        width: '100%',
        maxWidth: layout.maxWidth,
        // Provide the outer inset; content containers can then be full-width inside this.
        paddingHorizontal: Platform.select({ ios: 0, web: theme.margins.md, default: theme.margins.sm }),
    },
    header: {
        paddingTop: Platform.select({ ios: 28, web: 10, default: 14 }),
        paddingBottom: Platform.select({ ios: 6, web: 6, default: 8 }),
        // Align header label with the first line of Item text (outer inset + item padding).
        paddingHorizontal: Platform.select({ ios: 24, web: theme.margins.md + theme.margins.lg, default: 16 }),
    },
    headerNoTitle: {
        paddingTop: Platform.select({ ios: 18, web: 10, default: 14 }),
    },
    headerText: {
        ...Typography.default('regular'),
        color: theme.colors.groupped.sectionTitle,
        fontSize: Platform.select({ ios: 13, web: 12, default: 13 }),
        lineHeight: Platform.select({ ios: 18, default: 20 }),
        letterSpacing: Platform.select({ ios: -0.08, default: 0.1 }),
        textTransform: 'uppercase',
        fontWeight: Platform.select({ ios: 'normal', default: '500' }),
    },
    contentContainer: {
        backgroundColor: theme.colors.surface,
        marginHorizontal: Platform.select({ ios: 14, web: 0, default: 12 }),
        borderRadius: Platform.select({ ios: 10, web: 12, default: 12 }),
        overflow: 'hidden',
        ...(Platform.OS === 'web'
            ? {
                borderWidth: StyleSheet.hairlineWidth,
                borderColor: theme.colors.divider,
            }
            : {
                shadowColor: theme.colors.shadow.color,
                shadowOffset: { width: 0, height: 0.33 },
                shadowOpacity: theme.colors.shadow.opacity,
                shadowRadius: 0,
                elevation: 1,
            }),
    },
    footer: {
        paddingTop: Platform.select({ ios: 6, default: 8 }),
        paddingBottom: Platform.select({ ios: 8, web: 10, default: 12 }),
        paddingHorizontal: Platform.select({ ios: 24, web: theme.margins.md + theme.margins.lg, default: 16 }),
    },
    footerText: {
        ...Typography.default('regular'),
        color: theme.colors.groupped.sectionTitle,
        fontSize: Platform.select({ ios: 13, web: 12, default: 13 }),
        lineHeight: Platform.select({ ios: 18, default: 20 }),
        letterSpacing: Platform.select({ ios: -0.08, default: 0 }),
    },
}));

export const ItemGroup = React.memo<ItemGroupProps>((props) => {
    const { theme } = useUnistyles();
    const styles = stylesheet;

    const {
        title,
        footer,
        children,
        style,
        headerStyle,
        footerStyle,
        titleStyle,
        footerTextStyle,
        containerStyle
    } = props;

    return (
        <View style={[styles.wrapper, style]}>
            <View style={styles.container}>
                {/* Header */}
                {title ? (
                    <View style={[styles.header, headerStyle]}>
                        {typeof title === 'string' ? (
                            <Text style={[styles.headerText, titleStyle]}>
                                {title}
                            </Text>
                        ) : (
                            title
                        )}
                    </View>
                ) : (
                    // Add top margin when there's no title
                    <View style={styles.headerNoTitle} />
                )}

                {/* Content Container */}
                <View style={[styles.contentContainer, containerStyle]}>
                    {React.Children.map(children, (child, index) => {
                        if (React.isValidElement<ItemChildProps>(child)) {
                            // Don't add props to React.Fragment
                            if (child.type === React.Fragment) {
                                return child;
                            }
                            const isLast = index === React.Children.count(children) - 1;
                            const childProps = child.props as ItemChildProps;
                            return React.cloneElement(child, {
                                ...childProps,
                                showDivider: !isLast && childProps.showDivider !== false
                            });
                        }
                        return child;
                    })}
                </View>

                {/* Footer */}
                {footer && (
                    <View style={[styles.footer, footerStyle]}>
                        <Text style={[styles.footerText, footerTextStyle]}>
                            {footer}
                        </Text>
                    </View>
                )}
            </View>
        </View>
    );
});
