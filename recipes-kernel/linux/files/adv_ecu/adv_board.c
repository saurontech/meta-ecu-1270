#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>

#include <linux/fs.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/gpio.h>
#include <linux/delay.h>

#include "board-name.h"

static char board_name[32] = { 0 };

static int board_proc_show(struct seq_file *m, void *v)
{
	seq_printf(m, "%s", board_name);
	return 0;
}

static int board_proc_open(struct inode *inode, struct file *file)
{
	return single_open(file, board_proc_show, NULL);
}

static const struct proc_ops board_proc_fops = {
	.proc_open		= board_proc_open,
	.proc_read		= seq_read,
	.proc_lseek		= seq_lseek,
	.proc_release	= single_release,
};

static int __init proc_board_init(void)
{
	proc_create("board", 0, NULL, &board_proc_fops);
	return 0;
}

#define GPIO_TO_PIN(bank, gpio) 				(32 * (bank - 1) + (gpio))
#define MINI_PCIE_POWER_RESET_DELAY            	500 // 500 ms
#define MINI_PCIE_RESET_DELAY                  	100 // 100ms

static int gpio_reset_one(int base, int num, int time)
{
#if defined(CONFIG_MACH_ECU1270)
	int gpio;
	if (0 == base)
		gpio = 512 + num;
	else if (1 == base)
		gpio = 599 + num;
#else
	int gpio = GPIO_TO_PIN(base, num);
#endif
	if (gpio_request_one(gpio, GPIOF_OUT_INIT_HIGH, "gpio_out") < 0) {
		pr_err("Failed to request GPIO%d for GPIO%d_%d\n", gpio, base,num);
		return -1;
	}

	gpio_set_value(gpio, 0);
	mdelay(time);

	gpio_set_value(gpio, 1);

	//gpio_free(gpio);
	return 0;
}

static void minipcie_reset(void)
{
#if defined(CONFIG_MACH_ECU1270)
	// Minipcie Module Reset
	gpio_reset_one(0, 10, MINI_PCIE_RESET_DELAY); // MINIPCIE reset
#endif
}

static int adv_board_probe(struct platform_device *pdev)
{
	const char *bd_name;
	struct device *dev = &pdev->dev;
	struct device_node *np = dev->of_node;

	if (!np) {
		dev_err(dev, "No device tree node found\n");
		return -ENODEV;
	}

	if (of_property_read_string(np, "board_name", &bd_name)) {
		dev_err(dev, "Failed to read bd_name from device tree\n");
		return -EINVAL;
	}

	snprintf(board_name, sizeof(board_name), "%s\n", bd_name); 
	printk("+++%s init.\n", board_name);
	proc_board_init();
	minipcie_reset();

	dev_info(dev, "board name from device tree: %s\n", bd_name);
	return 0;
}

static const struct of_device_id adv_board_of_match[] = {
	{ .compatible = "custom,adv-board", },
	{},
};
MODULE_DEVICE_TABLE(of, adv_board_of_match);

static struct platform_driver adv_board_driver = {
	.probe = adv_board_probe,
	.driver = {
		.name = "adv_board",
		.of_match_table = adv_board_of_match,
	},
};

static int __init adv_board_init(void)
{
	int ret = platform_driver_register(&adv_board_driver);
	if (!ret) {
		printk(KERN_ERR "adv_board: %s\n", "Registerered");
	} else {
		printk(KERN_ERR "adv_board: %s\n", "Failed");
	}
	
	return ret;
}

static void __exit adv_board_exit(void)
{
	remove_proc_entry("board", NULL);
	platform_driver_unregister(&adv_board_driver);
}

module_init(adv_board_init);
module_exit(adv_board_exit);

MODULE_AUTHOR("Yuyan.Tsai");
MODULE_DESCRIPTION("Advantech board driver");
MODULE_LICENSE("GPL v2");

