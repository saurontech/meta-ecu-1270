// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * fm25.c -- support SPI FRAMs, such as Cypress FM25 models
 *
 * Copyright (C) 2014 Jiri Prchal
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#include <linux/bits.h>
#include <linux/delay.h>
#include <linux/device.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/property.h>
#include <linux/sched.h>
#include <linux/slab.h>
#include <linux/cdev.h>
#include <linux/spi/eeprom.h>
#include <linux/spi/spi.h>

#include <linux/nvmem-provider.h>

#define	FM25_SN_LEN		8		/* serial number length */
#define EE_MAXADDRLEN	3		/* 24 bit addresses, up to 2 MBytes */
#define DEV_NAME  		"fram"

struct fm25_data {
	struct spi_eeprom	chip;
	struct spi_device	*spi;
	struct mutex		lock;
	unsigned			addrlen;
	struct nvmem_config	nvmem_config;
	struct nvmem_device	*nvmem;
	u8 sernum[FM25_SN_LEN];
	u8 command[EE_MAXADDRLEN + 1];
	struct cdev cdev;
	int open_cnt;	
};

#define	FM25_WREN	0x06		/* latch the write enable */
#define	FM25_WRDI	0x04		/* reset the write enable */
#define	FM25_RDSR	0x05		/* read status register */
#define	FM25_WRSR	0x01		/* write status register */
#define	FM25_READ	0x03		/* read byte(s) */
#define	FM25_WRITE	0x02		/* write byte(s)/sector */
#define	FM25_SLEEP	0xb9		/* enter sleep mode */
#define	FM25_RDID	0x9f		/* read device ID */
#define	FM25_RDSN	0xc3		/* read S/N */

#define	FM25_SR_WEN	0x02		/* write enable (latched) */
#define	FM25_SR_BP0	0x04		/* BP for software writeprotect */
#define	FM25_SR_BP1	0x08
#define	FM25_SR_WPEN	0x80	/* writeprotect enable */
#define	FM25_SR_nRDY	0x01	/* nRDY = write-in-progress */

#define	FM25_INSTR_BIT3	0x08	/* additional address bit in instr */

#define	FM25_ID_LEN		9		/* ID length */

/*
 * Specs often allow 5ms for a page write, sometimes 20ms;
 * it's important to recover from write timeouts.
 */
#define	EE_TIMEOUT		25

#define	io_limit		PAGE_SIZE	/* bytes */

static int major;
static struct class *fram_class;

/*-------------------------------------------------------------------------*/

static int fm25_fram_read(void *priv, unsigned int offset,
			void *val, size_t count)
{
	struct fm25_data *fm25 = priv;
	char *buf = val;
	size_t max_chunk = spi_max_transfer_size(fm25->spi);
	unsigned int msg_offset = offset;
	size_t bytes_left = count;
	size_t segment;
	u8			*cp;
	ssize_t			status;
	struct spi_transfer	t[2];
	struct spi_message	m;
	u8			instr;

	if (unlikely(offset >= fm25->chip.byte_len))
		return -EINVAL;
	if ((offset + count) > fm25->chip.byte_len)
		count = fm25->chip.byte_len - offset;
	if (unlikely(!count))
		return -EINVAL;

	do {
		segment = min(bytes_left, max_chunk);
		cp = fm25->command;

		instr = FM25_READ;
		if (fm25->chip.flags & EE_INSTR_BIT3_IS_ADDR)
			if (msg_offset >= BIT(fm25->addrlen * 8))
				instr |= FM25_INSTR_BIT3;

		mutex_lock(&fm25->lock);

		*cp++ = instr;

		/* 8/16/24-bit address is written MSB first */
		switch (fm25->addrlen) {
		default:	/* case 3 */
			*cp++ = msg_offset >> 16;
			fallthrough;
		case 2:
			*cp++ = msg_offset >> 8;
			fallthrough;
		case 1:
		case 0:	/* can't happen: for better code generation */
			*cp++ = msg_offset >> 0;
		}

		spi_message_init(&m);
		memset(t, 0, sizeof(t));

		t[0].tx_buf = fm25->command;
		t[0].len = fm25->addrlen + 1;
		spi_message_add_tail(&t[0], &m);

		t[1].rx_buf = buf;
		t[1].len = segment;
		spi_message_add_tail(&t[1], &m);

		status = spi_sync(fm25->spi, &m);

		mutex_unlock(&fm25->lock);

		if (status)
			return status;

		msg_offset += segment;
		buf += segment;
		bytes_left -= segment;
	} while (bytes_left > 0);

	dev_dbg(&fm25->spi->dev, "read %zu bytes at %d\n",
		count, offset);
	return 0;
}

/* Read extra registers as ID or serial number */
static int fm25_aux_read(struct fm25_data *fm25, u8 *buf, uint8_t command,
			 int len)
{
	int status;
	struct spi_transfer t[2];
	struct spi_message m;

	spi_message_init(&m);
	memset(t, 0, sizeof(t));

	t[0].tx_buf = fm25->command;
	t[0].len = 1;
	spi_message_add_tail(&t[0], &m);

	t[1].rx_buf = buf;
	t[1].len = len;
	spi_message_add_tail(&t[1], &m);

	mutex_lock(&fm25->lock);

	fm25->command[0] = command;

	status = spi_sync(fm25->spi, &m);
	dev_dbg(&fm25->spi->dev, "read %d aux bytes --> %d\n", len, status);

	mutex_unlock(&fm25->lock);
	return status;
}

static ssize_t sernum_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	struct fm25_data *fm25;

	fm25 = dev_get_drvdata(dev);
	return sysfs_emit(buf, "%*ph\n", (int)sizeof(fm25->sernum), fm25->sernum);
}
static DEVICE_ATTR_RO(sernum);

static struct attribute *sernum_attrs[] = {
	&dev_attr_sernum.attr,
	NULL,
};
ATTRIBUTE_GROUPS(sernum);

static int fm25_fram_write(void *priv, unsigned int off, void *val, size_t count)
{
	struct fm25_data *fm25 = priv;
	size_t maxsz = spi_max_transfer_size(fm25->spi);
	const char *buf = val;
	int			status = 0;
	unsigned		buf_size;
	u8			*bounce;

	if (unlikely(off >= fm25->chip.byte_len))
		return -EFBIG;
	if ((off + count) > fm25->chip.byte_len)
		count = fm25->chip.byte_len - off;
	if (unlikely(!count))
		return -EINVAL;

	/* Temp buffer starts with command and address */
	buf_size = fm25->chip.page_size;
	if (buf_size > io_limit)
		buf_size = io_limit;
	bounce = kmalloc(buf_size + fm25->addrlen + 1, GFP_KERNEL);
	if (!bounce)
		return -ENOMEM;

	/*
	 * For write, rollover is within the page ... so we write at
	 * most one page, then manually roll over to the next page.
	 */
	mutex_lock(&fm25->lock);
	do {
		unsigned long	timeout, retries;
		unsigned	segment;
		unsigned	offset = off;
		u8		*cp = bounce;
		int		sr;
		u8		instr;

		*cp = FM25_WREN;
		status = spi_write(fm25->spi, cp, 1);
		if (status < 0) {
			dev_dbg(&fm25->spi->dev, "WREN --> %d\n", status);
			break;
		}

		instr = FM25_WRITE;
		if (fm25->chip.flags & EE_INSTR_BIT3_IS_ADDR)
			if (offset >= BIT(fm25->addrlen * 8))
				instr |= FM25_INSTR_BIT3;
		*cp++ = instr;

		/* 8/16/24-bit address is written MSB first */
		switch (fm25->addrlen) {
		default:	/* case 3 */
			*cp++ = offset >> 16;
			fallthrough;
		case 2:
			*cp++ = offset >> 8;
			fallthrough;
		case 1:
		case 0:	/* can't happen: for better code generation */
			*cp++ = offset >> 0;
		}

		/* Write as much of a page as we can */
		segment = buf_size - (offset % buf_size);
		if (segment > count)
			segment = count;
		if (segment > maxsz)
			segment = maxsz;
		memcpy(cp, buf, segment);
		status = spi_write(fm25->spi, bounce,
				segment + fm25->addrlen + 1);
		dev_dbg(&fm25->spi->dev, "write %u bytes at %u --> %d\n",
			segment, offset, status);
		if (status < 0)
			break;

		/*
		 * REVISIT this should detect (or prevent) failed writes
		 * to read-only sections of the EEPROM...
		 */

		/* Wait for non-busy status */
		timeout = jiffies + msecs_to_jiffies(EE_TIMEOUT);
		retries = 0;
		do {
			sr = spi_w8r8(fm25->spi, FM25_RDSR);
			if (sr < 0 || (sr & FM25_SR_nRDY)) {
				dev_dbg(&fm25->spi->dev,
					"rdsr --> %d (%02x)\n", sr, sr);
				/* at HZ=100, this is sloooow */
				msleep(1);
				continue;
			}
			if (!(sr & FM25_SR_nRDY))
				break;
		} while (retries++ < 3 || time_before_eq(jiffies, timeout));

		if ((sr < 0) || (sr & FM25_SR_nRDY)) {
			dev_err(&fm25->spi->dev,
				"write %u bytes offset %u, timeout after %u msecs\n",
				segment, offset,
				jiffies_to_msecs(jiffies -
					(timeout - EE_TIMEOUT)));
			status = -ETIMEDOUT;
			break;
		}

		off += segment;
		buf += segment;
		count -= segment;

	} while (count > 0);

	mutex_unlock(&fm25->lock);

	kfree(bounce);
	return status;
}

/*-------------------------------------------------------------------------*/

static int fm25_fram_to_chip(struct device *dev, struct spi_eeprom *chip)
{
	struct fm25_data *fm25 = container_of(chip, struct fm25_data, chip);
	u8 sernum[FM25_SN_LEN];
	u8 id[FM25_ID_LEN];
	int i;

	strscpy(chip->name, "fm25", sizeof(chip->name));

	/* Get ID of chip */
	fm25_aux_read(fm25, id, FM25_RDID, FM25_ID_LEN);
	if (id[6] != 0xc2) {
		dev_err(dev, "Error: no Cypress FRAM (id %02x)\n", id[6]);
		return -ENODEV;
	}
	/* Set size found in ID */
	if (id[7] < 0x21 || id[7] > 0x26) {
		dev_err(dev, "Error: unsupported size (id %02x)\n", id[7]);
		return -ENODEV;
	}

	chip->byte_len = BIT(id[7] - 0x21 + 4) * 1024;
	if (chip->byte_len > 64 * 1024)
		chip->flags |= EE_ADDR3;
	else
		chip->flags |= EE_ADDR2;

	if (id[8]) {
		fm25_aux_read(fm25, sernum, FM25_RDSN, FM25_SN_LEN);
		/* Swap byte order */
		for (i = 0; i < FM25_SN_LEN; i++)
			fm25->sernum[i] = sernum[FM25_SN_LEN - 1 - i];
	}

	chip->page_size = PAGE_SIZE;
	return 0;
}

/*-------------------------------------------------------------------------*/

static int fm25_device_open(struct inode *inode, struct file *filp)
{
	struct fm25_data *fm25 = container_of(inode->i_cdev, struct fm25_data, cdev);

	if (fm25->open_cnt)
        return -EBUSY;

	filp->private_data = fm25;
   	fm25->open_cnt++;

	return 0;
}

static int fm25_device_release(struct inode *inode, struct file *filp)
{
	struct fm25_data *fm25 = filp->private_data;
	fm25->open_cnt--;
	
	return 0;
}

static loff_t fm25_device_llseek(struct file *file, loff_t offset, int whence)
{
	loff_t newPos = 0;
	
    switch (whence) {
		case SEEK_SET:
			newPos = offset;
			break;
		case SEEK_CUR:
			newPos = file->f_pos + offset;
			break;
		case SEEK_END:
			newPos = offset;	
			break;
		default:
			offset = -1;
    }
    if (offset < 0 || newPos < 0)
        return -EINVAL;

    file->f_pos = newPos;

    return file->f_pos;
}

static ssize_t fm25_device_read(struct file *filp, char __user *buff, size_t count, loff_t *f_pos)
{
	int ret = 0;
	loff_t offset = *f_pos;
	struct fm25_data *fm25 = filp->private_data;
    char *kbuffer = NULL;

    if (count == 0)
		return -EINVAL;

	if (offset > fm25->chip.byte_len)
        return 0;
   
	if (offset + count > fm25->chip.byte_len)
		count = fm25->chip.byte_len - offset;

	kbuffer = kmalloc(count, GFP_KERNEL);
	if (!kbuffer)
		return -ENOMEM;

	ret = fm25_fram_read(fm25, offset, kbuffer, count);
	if (ret)
		goto out;
   
	if (copy_to_user(buff, kbuffer, count))
	{
		ret = -EFAULT;
		goto out;
	}
	*f_pos += count;    
	ret = count;
	
out:
    if (kbuffer)
		kfree(kbuffer);

	return ret;
}

static ssize_t fm25_device_write(struct file *filp, const char __user *buff, size_t count, loff_t * f_pos)
{
	int ret = 0;
	loff_t offset = *f_pos;	
	struct fm25_data *fm25 = filp->private_data;
    char *kbuffer = NULL;

    if (count == 0)
		return -EINVAL;

	if (offset > fm25->chip.byte_len)
        return 0;
	
	if (offset + count > fm25->chip.byte_len)
		count = fm25->chip.byte_len - offset;

	kbuffer = kmalloc(count, GFP_KERNEL);
	if (!kbuffer)
    	return -ENOMEM;

	if (copy_from_user(kbuffer, buff, count))    
	{
		ret = -EFAULT;
		goto out;
	}
	ret = fm25_fram_write(fm25, offset, (void *)kbuffer, count);
	if (ret)
		goto out;
	*f_pos += count;
	ret = count;
	
out:
    if (kbuffer)
		kfree(kbuffer);

	return ret;
}

struct file_operations fm25_fops = {
	.owner	=  THIS_MODULE,
	.open	=  fm25_device_open,
	.write	=  fm25_device_write,
	.read	=  fm25_device_read,
	.llseek  = fm25_device_llseek,
	.release = fm25_device_release,
};

int fm25_device_init(struct fm25_data *fm25)
{
	int ret;
	dev_t fm25_dev;
	struct device *device;

	ret = alloc_chrdev_region(&fm25_dev, 0, 1, DEV_NAME);
	if (ret) {
		pr_err("failed to allocate char dev region\n");
		return ret;
	}

	major = MAJOR(fm25_dev);
	cdev_init(&fm25->cdev, &fm25_fops);
	fm25->cdev.owner = THIS_MODULE;
	ret = cdev_add(&fm25->cdev, fm25_dev, 1);
	if (ret) {
		pr_err("Failed to add cdev. Aborting.\n");
		goto out_err;
	}	

	fram_class = class_create(DEV_NAME);
	if (IS_ERR(fram_class)) {
		ret = PTR_ERR(fram_class);
		goto out_err;
	}

	device = device_create(fram_class, NULL, MKDEV(major, 0), NULL, "%s%u", DEV_NAME, 0);
	if (IS_ERR(device)) {
		pr_err("device create failed!\n");
		ret = -ENODEV;
		goto out_err_1;
	}

	return 0;

out_err_1:
	class_destroy(fram_class);

out_err:
	unregister_chrdev_region(fm25_dev, 1);

	return ret;
}			   

/*-------------------------------------------------------------------------*/

static const struct of_device_id fm25_of_match[] = {
	{ .compatible = "cypress,fm25" },
	{ }
};
MODULE_DEVICE_TABLE(of, fm25_of_match);

static const struct spi_device_id fm25_spi_ids[] = {
	{ .name = "fm25" },
	{ }
};
MODULE_DEVICE_TABLE(spi, fm25_spi_ids);

static int fm25_probe(struct spi_device *spi)
{
	struct fm25_data	*fm25 = NULL;
	int			err;
	int			sr;
	struct spi_eeprom *pdata;

	/*
	 * Ping the chip ... the status register is pretty portable,
	 * unlike probing manufacturer IDs. We do expect that system
	 * firmware didn't write it in the past few milliseconds!
	 */
	sr = spi_w8r8(spi, FM25_RDSR);
	if (sr < 0 || sr & FM25_SR_nRDY) {
		dev_dbg(&spi->dev, "rdsr --> %d (%02x)\n", sr, sr);
		return -ENXIO;
	}

	fm25 = devm_kzalloc(&spi->dev, sizeof(*fm25), GFP_KERNEL);
	if (!fm25)
		return -ENOMEM;

	mutex_init(&fm25->lock);
	fm25->spi = spi;
	fm25->open_cnt = 0;
	spi_set_drvdata(spi, fm25);

	/* Chip description */
	pdata = dev_get_platdata(&spi->dev);
	if (pdata) {
		fm25->chip = *pdata;
	} else {
		err = fm25_fram_to_chip(&spi->dev, &fm25->chip);
		if (err)
		{
			goto out_err;
		}
	}

	/* For now we only support 8/16/24 bit addressing */
	if (fm25->chip.flags & EE_ADDR1)
		fm25->addrlen = 1;
	else if (fm25->chip.flags & EE_ADDR2)
		fm25->addrlen = 2;
	else if (fm25->chip.flags & EE_ADDR3)
		fm25->addrlen = 3;
	else {
		dev_dbg(&spi->dev, "unsupported address type\n");
		err = -EINVAL;
		goto out_err;
	}

	fm25->nvmem_config.type = NVMEM_TYPE_FRAM;
	fm25->nvmem_config.name = dev_name(&spi->dev);
	fm25->nvmem_config.dev = &spi->dev;
	fm25->nvmem_config.read_only = fm25->chip.flags & EE_READONLY;
	fm25->nvmem_config.root_only = true;
	fm25->nvmem_config.owner = THIS_MODULE;
	fm25->nvmem_config.compat = true;
	fm25->nvmem_config.base_dev = &spi->dev;
	fm25->nvmem_config.reg_read = fm25_fram_read;
	fm25->nvmem_config.reg_write = fm25_fram_write;
	fm25->nvmem_config.priv = fm25;
	fm25->nvmem_config.stride = 1;
	fm25->nvmem_config.word_size = 1;
	fm25->nvmem_config.size = fm25->chip.byte_len;

	fm25->nvmem = devm_nvmem_register(&spi->dev, &fm25->nvmem_config);
	if (IS_ERR(fm25->nvmem)) {
		err = PTR_ERR(fm25->nvmem);
		goto out_err;
	}

	err = fm25_device_init(fm25);
	if (err) {
		pr_err("fm25 device init failed!\n");
		goto out_err;
	}

	dev_info(&spi->dev, "%d %s %s %s%s, pagesize %u\n",
		 (fm25->chip.byte_len < 1024) ?
			fm25->chip.byte_len : (fm25->chip.byte_len / 1024),
		 (fm25->chip.byte_len < 1024) ? "Byte" : "KByte",
		 fm25->chip.name, "fram",
		 (fm25->chip.flags & EE_READONLY) ? " (readonly)" : "",
		 fm25->chip.page_size);

	return 0;
	
out_err:
	kfree(fm25);
	return err;
}

/*-------------------------------------------------------------------------*/

static struct spi_driver fm25_driver = {
	.driver = {
		.name		= "fm25",
		.of_match_table = fm25_of_match,
		.dev_groups	= sernum_groups,
	},
	.probe		= fm25_probe,
	.id_table	= fm25_spi_ids,
};

module_spi_driver(fm25_driver);

MODULE_DESCRIPTION("Driver for Cypress SPI FRAMs");
MODULE_AUTHOR("Jiri Prchal");
MODULE_LICENSE("GPL");
MODULE_ALIAS("spi:fram");
